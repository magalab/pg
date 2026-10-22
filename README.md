# PostgreSQL 测试镜像

这是一个基于官方 Alpine 源码构建的精简 PostgreSQL 镜像，不依赖其他 PostgreSQL 或 Alpine 衍生镜像。镜像保留英文和中文 ICU 排序规则，移除了 LLVM/JIT、contrib 扩展和可选过程语言运行时，适合本地开发和 CI 集成测试。

## 构建镜像

构建时需要指定 PostgreSQL 完整版本和主版本号：

```sh
docker build \
  --build-arg PG_VERSION=18.1 \
  --build-arg PG_MAJOR=18 \
  -t pg-test:18 .
```

以上版本仅为示例。建议固定测试使用的 PostgreSQL 版本，避免重新构建时版本意外变化。

默认 Alpine 版本为 `latest`。需要可重复构建时，可指定 `ALPINE_VERSION`，例如：

```sh
docker build \
  --build-arg PG_VERSION=18.1 \
  --build-arg PG_MAJOR=18 \
  --build-arg ALPINE_VERSION=3.24 \
  -t pg-test:18 .
```

ICU 数据会使用构建所选 Alpine 版本对应的 ICU 版本生成。

## GitHub Actions 构建与发布

GitHub Actions 每周一 UTC 03:23 自动检查 PostgreSQL 上游版本，并构建、验证和发布最新稳定版本。需要时也可以手动运行；留空 `pg_version` 时构建最新稳定版本，填写版本号时构建指定版本。工作流从 GitHub 仓库信息生成 GHCR 镜像地址 `ghcr.io/<所有者>/<仓库>`，例如本仓库对应 `ghcr.io/magalab/pg`。

工作流分别在原生 amd64 和 arm64 runner 上构建并启动对应架构的容器，不使用 QEMU；随后检查健康状态、中英文 ICU 排序和 SQL 初始化脚本。两种架构都验证通过后，工作流会发布 GHCR 多架构镜像。

## 发布镜像和标签

镜像地址会根据当前 GitHub 仓库自动生成，格式为 `ghcr.io/<所有者>/<仓库>`。以 `ghcr.io/magalab/pg` 为例，假设 PostgreSQL 最新稳定版本为 `18.1`，标签如下：

```text
ghcr.io/magalab/pg:latest  # 最新稳定的大版本和小版本
ghcr.io/magalab/pg:18     # PostgreSQL 18 系列最新小版本
ghcr.io/magalab/pg:18.1   # 指定 PostgreSQL 版本
```

自动构建最新稳定版本时会发布完整版本、对应系列和 `latest` 标签。手动指定非最新版本时，只发布对应的完整版本标签，避免旧版本构建覆盖 `latest` 或系列标签。

## 启动容器

```sh
docker run --rm --name pg-test \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=test \
  -e PUID=70 -e PGID=70 \
  -e UMASK=022 -e TZ=Asia/Shanghai \
  -p 5432:5432 \
  ghcr.io/magalab/pg:18
```

容器监听 5432 端口。首次启动时，`POSTGRES_USER`、`POSTGRES_PASSWORD` 和 `POSTGRES_DB` 用于初始化数据库。`PUID`/`PGID` 设置 postgres 账户的 UID/GID（默认均为 70）；`UMASK` 设置文件权限掩码（默认 `022`）；`TZ` 设置容器时区（默认 `Asia/Shanghai`）。

镜像内置 `pg_isready` 健康检查，可供 Docker Compose 或 CI 判断 PostgreSQL 是否已准备好接受连接。

容器以 root 启动时，入口脚本会应用 PUID/PGID 并调整时区文件，随后 PostgreSQL 会降权为 postgres 用户运行。也可以用非 root 用户启动，但容器运行时 UID/GID 必须与 PUID/PGID 相同。

数据目录为 `/var/lib/postgresql/<主版本号>/docker`。需要在容器替换后保留数据时，请挂载父目录 `/var/lib/postgresql`。放在 `/docker-entrypoint-initdb.d` 下的 `.sh`、`.sql` 和 `.sql.gz` 文件会在首次初始化时执行。

## 中英文 ICU 排序

镜像包含 PostgreSQL ICU 支持，以及精简的英文（`en`）和中文（`zh`）ICU 数据包。初始化时可以指定集群默认排序规则：

```sh
docker run --rm \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_INITDB_ARGS='--locale-provider=icu --icu-locale=zh' \
  ghcr.io/magalab/pg:18
```

将 `--icu-locale=zh` 改为 `--icu-locale=en` 可使用英文作为集群默认规则。也可以在创建数据库时单独选择 ICU locale。镜像不包含其他语言的完整 ICU 数据。

## 为精简体积移除的功能

- LLVM/JIT 和所有 contrib 扩展
- GSSAPI、LDAP、libcurl、liburing、XML 和 XSLT 支持
- Perl、Python、Tcl 过程语言运行时
- s6 init 和通用 `/config` 卷约定；PostgreSQL 使用 `/var/lib/postgresql` 保存数据及配置
- `.sql.xz` 和 `.sql.zst` 初始化脚本格式

常见集成测试所需的 PostgreSQL 服务端、客户端、`initdb`、密码初始化，以及 SQL 和 Shell 初始化脚本仍然可用。

---

# PostgreSQL Test Image (English)

A slim PostgreSQL image built from official Alpine Linux images and PostgreSQL source. It does not depend on third-party PostgreSQL or Alpine-derived images. The image retains English and Chinese ICU collations while omitting LLVM/JIT, contrib extensions, and optional procedural language runtimes. It is intended for local development and CI integration tests.

## Build the image

Specify both the full PostgreSQL version and its major version:

```sh
docker build \
  --build-arg PG_VERSION=18.1 \
  --build-arg PG_MAJOR=18 \
  -t pg-test:18 .
```

The version above is an example. Pin the PostgreSQL version used by your tests to avoid unexpected changes on rebuild.

The default Alpine tag is `latest`. For a more repeatable build, set `ALPINE_VERSION` explicitly:

```sh
docker build \
  --build-arg PG_VERSION=18.1 \
  --build-arg PG_MAJOR=18 \
  --build-arg ALPINE_VERSION=3.24 \
  -t pg-test:18 .
```

ICU data is built with the ICU version provided by the selected Alpine release.

## GitHub Actions builds and publishing

GitHub Actions checks upstream PostgreSQL releases every Monday at 03:23 UTC, then builds, validates, and publishes the latest stable release. You can also run it manually. Leave `pg_version` blank to build the latest stable release, or enter a version to build that specific release. The workflow derives the GHCR image address from GitHub repository metadata in the form `ghcr.io/<owner>/<repository>`; for this repository, that is `ghcr.io/magalab/pg`.

The workflow builds and starts each architecture on native amd64 and arm64 runners without QEMU. It checks container health, English and Chinese ICU collations, and SQL initialization scripts. The multi-architecture image is published only after both builds pass.

## Image tags

The image address is generated from the current GitHub repository in the form `ghcr.io/<owner>/<repository>`. For example, if the latest stable PostgreSQL release is `18.1`, the tags are:

```text
ghcr.io/magalab/pg:latest  # Latest stable PostgreSQL release
ghcr.io/magalab/pg:18      # Latest release in PostgreSQL 18 series
ghcr.io/magalab/pg:18.1    # Exact PostgreSQL release
```

An automatic build of the latest stable release publishes its exact version, series, and `latest` tags. A manual build of an older release publishes only its exact version tag, so it cannot overwrite `latest` or the series tag.

## Run the container

```sh
docker run --rm --name pg-test \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_DB=test \
  -e PUID=70 -e PGID=70 \
  -e UMASK=022 -e TZ=Asia/Shanghai \
  -p 5432:5432 \
  ghcr.io/magalab/pg:18
```

The container listens on port 5432. On first startup, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` initialize the database. `PUID` and `PGID` set the postgres account UID and GID (both default to 70); `UMASK` sets the file mode mask (default `022`); `TZ` sets the container timezone (default `Asia/Shanghai`).

The image includes a `pg_isready` health check for Docker Compose and CI to determine when PostgreSQL is ready to accept connections.

When started as root, the entrypoint applies `PUID`/`PGID` and configures the timezone before PostgreSQL drops privileges to the postgres user. The image can also run as a non-root user if its runtime UID and GID match `PUID` and `PGID`.

The data directory is `/var/lib/postgresql/<major-version>/docker`. Mount `/var/lib/postgresql` to retain data when replacing the container. Files under `/docker-entrypoint-initdb.d` ending in `.sh`, `.sql`, and `.sql.gz` run during first-time initialization.

## English and Chinese ICU collations

The image includes PostgreSQL ICU support and a reduced ICU data bundle for English (`en`) and Chinese (`zh`). Choose the default cluster collation during initialization:

```sh
docker run --rm \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -e POSTGRES_INITDB_ARGS='--locale-provider=icu --icu-locale=zh' \
  ghcr.io/magalab/pg:18
```

Change `--icu-locale=zh` to `--icu-locale=en` to use English as the cluster default. You can also select an ICU locale for an individual database. The image does not include full ICU data for other languages.

## Features omitted to reduce image size

- LLVM/JIT and all contrib extensions
- GSSAPI, LDAP, libcurl, liburing, XML, and XSLT support
- Perl, Python, and Tcl procedural language runtimes
- s6 init and the generic `/config` volume convention; PostgreSQL stores data and configuration under `/var/lib/postgresql`
- `.sql.xz` and `.sql.zst` initialization script formats

The PostgreSQL server and client tools, `initdb`, password initialization, and SQL and shell initialization scripts remain available for common integration tests.
