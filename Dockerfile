# syntax=docker/dockerfile:1.4

# ============================================================
# Docker build arguments
#   PG_VERSION    : PostgreSQL full version to build, e.g. 18.6 (required)
#   PG_MAJOR      : PostgreSQL major version, e.g. 18 (required; must match PG_VERSION)
#   ALPINE_VERSION: Alpine tag used for builder and runtime, defaults to latest
# ============================================================
ARG ALPINE_VERSION=latest

# ============================================================
# Stage 1: compile PostgreSQL from source
# ============================================================
FROM alpine:${ALPINE_VERSION} AS builder

ARG PG_VERSION
ARG PG_MAJOR

ENV PG_VERSION=${PG_VERSION} \
    PG_MAJOR=${PG_MAJOR}

# runtime shared-library collector
COPY --chmod=755 deplib/cplibfiles.sh /usr/local/bin/cplibfiles.sh

# download and verify the official source tarball, then compile
RUN --mount=type=cache,target=/var/cache/apk \
    set -eux; \
    test -n "$PG_VERSION" || { echo "ERROR: PG_VERSION build arg is required" >&2; exit 1; }; \
    test -n "$PG_MAJOR" || { echo "ERROR: PG_MAJOR build arg is required" >&2; exit 1; }; \
    actual_major="${PG_VERSION%%.*}"; \
    test "$PG_MAJOR" = "$actual_major" || { echo "ERROR: PG_MAJOR=$PG_MAJOR does not match PG_VERSION=$PG_VERSION" >&2; exit 1; }; \
    \
    wget -O postgresql-$PG_VERSION.tar.bz2 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2"; \
    wget -O postgresql-$PG_VERSION.tar.bz2.sha256 "https://ftp.postgresql.org/pub/source/v$PG_VERSION/postgresql-$PG_VERSION.tar.bz2.sha256"; \
    sha256sum -c postgresql-$PG_VERSION.tar.bz2.sha256; \
    mkdir -p /usr/src/postgresql; \
    tar \
        --extract \
        --file postgresql-$PG_VERSION.tar.bz2 \
        --directory /usr/src/postgresql \
        --strip-components 1 \
    ; \
    rm postgresql-$PG_VERSION.tar.bz2 postgresql-$PG_VERSION.tar.bz2.sha256; \
    \
    apk add --no-cache --virtual .build-deps \
        bison \
        coreutils \
        dpkg-dev dpkg \
        flex \
        gcc \
        libc-dev \
        linux-headers \
        make \
        openssl-dev \
        perl \
        util-linux-dev \
        zlib-dev \
        icu-dev \
        lz4-dev \
        zstd-dev \
    ; \
    \
    cd /usr/src/postgresql; \
    # change DEFAULT_PGSOCKET_DIR to /var/run/postgresql (matching Debian)
    awk '$1 == "#define" && $2 == "DEFAULT_PGSOCKET_DIR" && $3 == "\"/tmp\"" { $3 = "\"/var/run/postgresql\""; print; next } { print }' src/include/pg_config_manual.h > src/include/pg_config_manual.h.new; \
    grep '/var/run/postgresql' src/include/pg_config_manual.h.new; \
    mv src/include/pg_config_manual.h.new src/include/pg_config_manual.h; \
    gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
    \
    ./configure \
        --enable-option-checking=fatal \
        --build="$gnuArch" \
        --enable-integer-datetimes \
        --disable-rpath \
        --with-uuid=e2fs \
        --with-pgport=5432 \
        --prefix=/usr/local \
        --with-includes=/usr/local/include \
        --with-libraries=/usr/local/lib \
        --with-icu \
        --with-lz4 \
        --with-openssl \
        --with-zstd \
    ; \
    make -j "$(nproc)" world-bin; \
    make install-world-bin; \
    # sanity check before build deps are removed
    postgres --version; \
    \
    # strip binaries and shared libraries to minimize image size
    find /usr/local -type f \( -name '*.so*' -o -perm -111 \) -exec strip --strip-unneeded {} + 2>/dev/null || true; \
    \
    # collect every runtime shared library (jellyfin style) BEFORE build deps are removed
    for bin in /usr/local/bin/* /usr/local/lib/postgresql/*.so; do \
        if [ -e "$bin" ]; then cplibfiles.sh "$bin" /out; fi; \
    done; \
    \
    # remove build deps and leftover residue
    apk del --no-network .build-deps; \
    cd /; \
    rm -rf \
        /usr/src/postgresql \
        /usr/local/share/doc \
        /usr/local/share/man \
        /var/cache/apk/* \
        /var/tmp/* \
    ;

# ============================================================
# Stage: compile ICU data with only en + zh locales
# Alpine ships only icu-data-en or icu-data-full; build a slim
# en+zh bundle so Chinese collation works without the full data
# ============================================================
FROM alpine:${ALPINE_VERSION} AS icu-data-builder

RUN set -eux; \
    apk add --no-cache \
        gcc \
        g++ \
        make \
        libc-dev \
        python3 \
        coreutils \
    ; \
    \
    # detect the ICU version shipped by this Alpine release (follows latest).
    # icu-libs alone has no /usr/share/icu; icu-data-en provides the initial
    # /usr/share/icu/<ver>/icudt*.dat (en only) that is replaced below.
    apk add --no-cache icu-libs icu-data-en; \
    icu_ver="$(ls /usr/share/icu/ | head -n1)"; \
    test -n "$icu_ver"; \
    echo "building ICU data for version: $icu_ver"; \
    \
    # download the matching ICU source tarball.
    # the Alpine data dir is the dot form "78.1" which matches the ICU GitHub
    # tag "release-78.1" (ICU >= 78); keep a dash fallback for older releases.
    icu_dash="${icu_ver//./-}"; \
    (wget -O /tmp/icu-src.tgz "https://github.com/unicode-org/icu/archive/refs/tags/release-${icu_ver}.tar.gz" \
        || wget -O /tmp/icu-src.tgz "https://github.com/unicode-org/icu/archive/refs/tags/release-${icu_dash}.tar.gz"); \
    test -s /tmp/icu-src.tgz; \
    \
    mkdir -p /usr/src/icu; \
    tar -zxf /tmp/icu-src.tgz -C /usr/src/icu --strip-components 1; \
    rm -f /tmp/icu-src.tgz \
    ;

# keep only the en and zh (all script/region variants) locale data
RUN cat > /tmp/filters.json <<'EOF'
{
  "localeFilter": {
    "filterType": "language",
    "includelist": ["en", "zh"]
  }
}
EOF

RUN set -eux; \
    # the release tarball is a monorepo; ICU4C sources live under icu4c/source
    cd /usr/src/icu/icu4c/source; \
    ICU_DATA_FILTER_FILE=/tmp/filters.json \
    ./runConfigureICU Linux \
        --disable-samples \
        --disable-tests \
        --disable-icuio \
        --disable-layoutex \
        --disable-extras \
        --with-data-packaging=archive \
    ; \
    make -j "$(nproc)"; \
    \
    # replace Alpine's en-only data (installed with icu-data-en) with the slim en+zh bundle
    icu_dat="$(find /usr/share/icu -name 'icudt*.dat' | head -n1)"; \
    test -n "$icu_dat"; \
    cp data/out/icudt*.dat "$icu_dat"; \
    ls -lh "$icu_dat" \
    ;

# ============================================================
# Stage 2: minimal runtime image assembled directly from official Alpine
# ============================================================
FROM alpine:${ALPINE_VERSION}

ARG PG_VERSION
ARG PG_MAJOR

LABEL description="Minimal PostgreSQL ${PG_VERSION} test image with English and Chinese ICU data"
LABEL org.opencontainers.image.source="https://github.com/magalab/pg"

ENV PG_VERSION=${PG_VERSION} \
    PG_MAJOR=${PG_MAJOR} \
    LANG=C.UTF-8 \
    TZ=Asia/Shanghai \
    PGDATA=/var/lib/postgresql/${PG_MAJOR}/docker

# create the postgres user/group (70 is the standard Alpine postgres uid/gid)
RUN set -eux; \
    addgroup -g 70 -S postgres; \
    adduser -u 70 -S -D -G postgres -H -h /var/lib/postgresql -s /bin/sh postgres; \
    install --verbose --directory --owner postgres --group postgres --mode 1777 /var/lib/postgresql; \
    mkdir -p /docker-entrypoint-initdb.d /var/run/postgresql; \
    chown postgres:postgres /docker-entrypoint-initdb.d /var/run/postgresql; \
    chmod 3777 /var/run/postgresql; \
    \
    rm -rf /var/cache/apk/* /var/tmp/* /tmp/* \
    ;

# copy the compiled PostgreSQL tree, its collected shared libraries, and the slim ICU data
COPY --from=builder /usr/local/ /usr/local/
COPY --from=builder /out/ /
COPY --from=icu-data-builder /usr/share/icu/ /usr/share/icu/

# make the sample config correct by default and install the minimal runtime tool
# (shared libraries are already copied from the builder; only non-library tools are installed)
RUN set -eux; \
    cp -v /usr/local/share/postgresql/postgresql.conf.sample /usr/local/share/postgresql/postgresql.conf.sample.orig; \
    sed -ri "s!^#?(listen_addresses)\s*=\s*\S+.*!\1 = '*'!" /usr/local/share/postgresql/postgresql.conf.sample; \
    grep -F "listen_addresses = '*'" /usr/local/share/postgresql/postgresql.conf.sample; \
    \
    apk add --no-cache shadow su-exec tzdata; \
    \
    rm -rf \
        /var/cache/apk/* \
        /var/tmp/* \
        /tmp/* \
    ;

# entrypoint / init scripts (based on docker-library/postgres)
COPY --chmod=755 root/ /

VOLUME /var/lib/postgresql
EXPOSE 5432
STOPSIGNAL SIGINT
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=12 CMD pg_isready -q -h /var/run/postgresql || exit 1

# Initialize runtime user, timezone, and umask before starting PostgreSQL.
ENTRYPOINT ["/init"]
CMD ["postgres"]
