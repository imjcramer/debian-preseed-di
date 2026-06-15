# Kernel Cmdline Examples

Serve `d-i/debian/preseed.cfg` from HTTP(S) and append the manual classes. The
installer auto-detects `arch`, `cpu`, `gpu`, and `disk`; use group-qualified
overrides such as `disk/nvme` only when detection must be overridden.

- Site: `prod`, `lab`, `dmz`
- Base role: `desktop`, `server`
- Security: `standard`, `enhanced`
- Network: `dhcp`, `static`
- Addons: `nvidia`, `ssh`

Auto-detected hardware and storage classes:

- `arch`: `amd64`, `arm64`
- `cpu`: `intel`, `amd`
- `gpu`: `intel-uhd`, `amd-radeon`, `generic`
- `disk`: `nvme`, `emmc`, `vm`

Example `desktop`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,desktop,standard,dhcp
```

Example `desktop with SSH server`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,desktop,standard,dhcp,ssh
```

Example `desktop with NVIDIA addon`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,desktop,standard,dhcp,nvidia
```

Example `desktop forcing eMMC storage override`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,desktop,standard,dhcp,disk/emmc
```

Example `server web role`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,server,enhanced,dhcp,web
```

Static-network example `server db role with NVIDIA addon`:

```text
auto=true priority=critical locale=en_US.UTF-8 language=en country=US \
url=http://<lan-host>:8080/d-i/debian/preseed.cfg \
classes=prod,server,enhanced,static,db,nvidia \
ip=192.0.2.10 netmask=255.255.255.0 gateway=192.0.2.1 nameservers=1.1.1.1,1.0.0.1
```
