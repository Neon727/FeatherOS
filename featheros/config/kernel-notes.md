# Kernel Config Notes — 512MB Floor, 2006+ Hardware

Decisions to make when running `make menuconfig` for the target kernel.
Hardware scope: 2006 onward, x86_64 only (no 32-bit-only support),
with no upper bound — 512MB is the RAM floor, not a ceiling, and the
system is expected to run well on newer/higher-spec machines too.

## General
- Single x86_64 kernel/base image — no dual-arch build needed since
  pre-2006 (32-bit-only) hardware is out of scope.
- Broad driver coverage as **loadable modules**, not built-in — this
  is a general-purpose distro for other people's hardware, not one
  known machine, so the kernel detects and loads only what's present
  rather than hand-picking drivers per install.
- Both BIOS (legacy) and UEFI boot support via GRUB — covers
  2006-2012ish BIOS-only machines and newer UEFI ones from one image.
- Disable debug symbols and most `CONFIG_DEBUG_*` options for the
  release kernel — they bloat the image and cost a bit of runtime
  overhead.
- Initramfs needs to carry storage/filesystem driver modules needed
  to mount root, since the exact disk controller isn't known ahead
  of time across varied hardware.

## Memory-relevant options
- `CONFIG_ZRAM` (compressed RAM-backed swap) — genuinely useful on a
  512MB target to extend usable memory without disk swap.
- `CONFIG_HIGHMEM` enabled, to support machines with RAM at or above
  the ~1GB range even though 512MB is the nominal floor — some "old
  hardware" units in scope may have more than the minimum.

## Graphics driver approach
- Default to open-source drivers: i915 (Intel), amdgpu/radeon (AMD),
  nouveau (Nvidia) — covers the 2006+ range reasonably well as
  modules.
- Treat proprietary Nvidia drivers as an optional post-install
  add-on rather than baking them into the base image (licensing +
  build complexity + they change often).
- VESA/fbdev as a fallback for anything undetected, so the desktop
  variant always has *some* display path even on unknown graphics.
