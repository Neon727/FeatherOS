# FeatherOS

*Newer software for older hardware.*

A custom Linux distro built via Linux From Scratch (LFS) for the
early stages (toolchain, minimal temp system), then bootstrapped via
`apk` for the real base system — leaning on Alpine's existing
musl-based package ecosystem rather than hand-compiling everything a
second time. Targets hardware from 2006 onward with no upper bound
(512MB RAM is the floor, not a ceiling — runs fine on newer machines
too).

## Architecture

- **libc**: musl, across both variants
- **Package manager**: apk-tools (Alpine's) — own repo for
  FeatherOS-specific packages, Alpine's repo for common software
- **Architecture**: x86_64 only, both BIOS and UEFI boot support
- **Init**: OpenRC
- **Drivers**: broad coverage built as loadable kernel modules, since
  this targets varied hardware, not one known machine

Two variants:
- **headless** — no GUI, built for servers/NAS/embedded use on
  older hardware
- **desktop** — general-purpose daily driver. i3 + Xorg, no display
  manager (X auto-starts on login instead). Default app set is
  deliberately minimal — just enough to function; everything else
  installs via `apk` after the fact rather than being bundled upfront

## Build pipeline

1. **Host prep** (`00-host-prep.sh`) — verifies the build host (an
   Alpine VM) has what Stage 1 needs.
2. **abuild setup** (`01-setup-abuild.sh`) — installs `abuild` and a
   signing key, for building FeatherOS's own `.apk` packages later.
3. **Get started** (`02-get-started.sh`) — ties host prep + abuild
   setup together, creates the LFS working directories.
4. **Stage 1: toolchain** (`03-stage1-toolchain.sh`) — builds an
   isolated binutils + musl + GCC into `$LFS_ROOT/tools`, independent
   of the host's exact package versions. Checkpointed — the GCC build
   is the long step.
5. **Stage 2: temp system** (`04-stage2-tempsystem.sh`) — builds a
   minimal chroot-able system using static busybox, built with the
   Stage 1 toolchain.
6. **Stage 3: base system** (`05-stage3-basesystem.sh`) — bootstraps
   the real base system via `apk` (`alpine-base` + `openrc`), the
   same method Alpine's own official tooling uses to build root
   filesystems.
7. **Kernel build** (`06-build-kernel.sh`) — compiles the actual
   bootable kernel (`bzImage`) from Stage 1's kernel source and
   installs its modules into the Stage 3 base system root. (Stage 1
   only extracts userspace API headers via `headers_install` — this
   is the step that produces a real, bootable kernel image.)
8. **Branding/config install** (`07-install-branding.sh`) — copies
   the splash, OpenRC services, MOTD, issue banner, os-release, and
   X auto-start script into the built root, and enables the splash
   services via `rc-update` inside a chroot. These exist as source
   files in this repo but don't install themselves — this is the
   step that actually puts them on the system being built.
9. **Initramfs** (`08-build-initramfs.sh`) — packages busybox + the
   init script + integrity-check scripts into the cpio+gzip image the
   kernel loads at boot.
10. **ISO build** (`11-build-iso.sh`) — stages the built root + kernel
    + initramfs, writes `grub.cfg`, runs `grub-mkrescue` for a hybrid
    BIOS+UEFI bootable image, then embeds a checksum
    (`10-embed-iso-checksum.sh`) as the final step.

Boot-time behavior, once an ISO is built:
- **`initramfs-init.sh`** runs first (PID 1), checks for the
  `featheros.checkmedia` boot parameter
- If set, **`iso-integrity-check.sh`** verifies the booted media
  against its embedded checksum — passes silently, or shows a
  warning with a y/n prompt on mismatch
- **`boot-integrity-check.sh`** + **`09-generate-integrity-manifest.sh`**
  do the same idea for individual critical files on the *installed*
  system — severity-tagged (a critical failure halts boot into a
  rescue shell, a warning-level one just shows and continues)
- **`splash-feather.sh`** (the ASCII spinning-feather boot splash)
  runs the integrity check concurrently in the background and shows
  live results underneath the animation

## Structure

```
distro-project/
├── scripts/
│   ├── 00-host-prep.sh
│   ├── 01-setup-abuild.sh
│   ├── 02-get-started.sh
│   ├── 03-stage1-toolchain.sh
│   ├── 04-stage2-tempsystem.sh
│   ├── 05-stage3-basesystem.sh
│   ├── 06-build-kernel.sh
│   ├── 07-install-branding.sh
│   ├── 08-build-initramfs.sh
│   ├── 09-generate-integrity-manifest.sh   (build-time)
│   ├── 10-embed-iso-checksum.sh            (build-time)
│   ├── 11-build-iso.sh
│   ├── boot-integrity-check.sh             (boot-time)
│   ├── initramfs-init.sh                   (boot-time, becomes /init)
│   ├── iso-integrity-check.sh              (boot-time)
│   ├── splash-feather.sh                   (boot-time)
│   ├── report-filecount.sh                 (diagnostic, run anytime)
│   └── lib/
│       ├── checkpoint.sh    # save/resume state for long build stages
│       └── colors.sh        # shared colored status tags
├── config/
│   ├── kernel-notes-public.md
│   ├── os-release
│   ├── etc-motd
│   ├── etc-issue
│   ├── etc-profile.d-start-xorg.sh
│   └── openrc/
│       ├── featheros-splash
│       └── featheros-splash-stop
├── package-lists/
│   ├── base.txt
│   ├── headless.txt
│   └── desktop.txt
├── package-template/
│   └── APKBUILD              # template for building FeatherOS's own packages
└── docs/
    ├── branding.md
    └── packaging-workflow.md
```

All stage scripts support `--status` and `--reset [step]` for
checking progress and redoing individual steps without starting a
whole stage over.

## Status

See `CHECKLIST.md` for what's built vs. actually verified on real
hardware yet — a lot of the pipeline is written and logic-tested but
hasn't been run end-to-end.

## License

MIT — see `LICENSE`. Covers FeatherOS's own scripts, configs,
branding, and docs. Third-party components pulled in by the build
(Linux kernel, GNU toolchain, musl, Alpine packages) keep their own
existing licenses.

Built ISOs aren't committed to this repo (see `.gitignore`) — they're
published via GitHub Releases instead, alongside a sha256 checksum,
so the repo stays lightweight and the release history stays clean.

## Contributing / building it yourself

See `docs/packaging-workflow.md` for how FeatherOS-specific `.apk`
packages get built. The build pipeline above is run on an Alpine VM —
each stage script is self-contained and documents its own
requirements at the top of the file.
