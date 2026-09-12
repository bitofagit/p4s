P4S export notes (Linux first)
==============================

Presets live in export_presets.cfg (tracked).

1. Install Godot 4.6 export templates
   Editor → Manage Export Templates → Download for 4.6.x

2. Export Linux x86_64 (this laptop)
   Project → Export → "Linux Desktop x86_64"
   Output: build/linux/p4s-linux-x86_64.x86_64
   Uses the project renderer (mobile / Vulkan) with OpenGL 3 fallback.

3. Optional potato SKU
   "Linux Desktop x86_64 (p4s_low_end)" sets custom feature p4s_low_end
   (forces MetaManager.low_end_gpu). Use for VMware / HD 520-class machines,
   not for Iris Xe — that GPU should stay on the default preset.

4. include_filter
   data/*.csv, data/*.json, data/almanac/*.md must ship or seed inventory
   is empty. Do not drop this filter.

5. .deb packaging (follow-up, not in this PR)
   After a playable binary exists:

     mkdir -p pkg/usr/games pkg/usr/share/p4s
     cp build/linux/p4s-linux-x86_64.x86_64 pkg/usr/games/p4s
     # plus .desktop + icon under usr/share/applications and usr/share/pixmaps
     # then fpm or dpkg-deb --build

   Track that work as a separate issue once the export is tested on the
   Pentium 7505 laptop.

6. Windows / Mac
   A Windows x86_64 stub is in export_presets.cfg. Mac/Windows installers
   are later targets; this pass is optimisation + a working Linux preset.
