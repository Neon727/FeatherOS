# FeatherOS Checklist

Status of the build pipeline and features. "Built" means the script
exists and its logic has been tested; "Verified" means it's actually
been run successfully end-to-end on real hardware/a real build.

## Build pipeline

- [x] Host prep (`00-host-prep.sh`)
- [x] abuild setup (`01-setup-abuild.sh`)
- [x] Get-started wrapper (`02-get-started.sh`)
- [ ] Stage 1: toolchain (`03-stage1-toolchain.sh`) — built, in progress verifying on real hardware
- [ ] Stage 2: temp system (`04-stage2-tempsystem.sh`) — built, not yet run
- [ ] Stage 3: base system (`05-stage3-basesystem.sh`) — built, not yet run
- [ ] Initramfs build (`06-build-initramfs.sh`) — built, not yet run
- [ ] Integrity manifest generation (`07-generate-integrity-manifest.sh`) — built, not yet run
- [ ] ISO checksum embedding (`08-embed-iso-checksum.sh`) — built, not yet run
- [ ] ISO build (`09-build-iso.sh`) — built, not yet run
- [ ] A full ISO has actually booted successfully

## Boot-time behavior

- [x] Checkpointed build stages (resume after failure without redoing completed steps)
- [x] ASCII boot splash with live integrity check results
- [x] Severity-based integrity checks (critical halts boot, warning continues)
- [x] ISO media integrity check (checksum mismatch warning + y/n prompt)
- [x] Auto-start X on login (desktop variant, no display manager)
- [ ] Verified on a real boot, not just logic-tested

## Branding

- [x] Name, slogan, color palette
- [x] Boot splash
- [x] MOTD / pre-login banner
- [x] Default wallpaper (dark + light gradient variants)
- [x] UI icon set chosen (Feather Icons)
- [ ] Logo/wordmark file
- [ ] GRUB boot menu theming — basic colors added, not yet seen on a real boot

## Packaging

- [x] Package manager chosen (apk-tools)
- [x] Base/headless/desktop package lists
- [x] APKBUILD template + packaging workflow docs
- [ ] An actual FeatherOS-specific package built and installed
- [ ] FeatherOS's own apk repo set up and hosted

## Variants

- [x] headless package list
- [x] desktop package list (i3, no DM, minimal default apps)
- [ ] Either variant actually built and booted

## Not started yet

- [ ] An actual installer (the build pipeline produces a bootable
      image; it doesn't yet walk a user through installing to disk)
- [ ] Kernel config tuned and tested against real target hardware
- [ ] Driver coverage tested on real varied hardware
- [ ] FeatherOS's own apk repo hosting/infrastructure
- [ ] Documentation site / wiki