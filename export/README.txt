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

5. .deb packaging (prep script; needs a tested Linux export)
   After exporting Linux Desktop x86_64:

     ./export/pack_deb.sh

   Writes build/linux/p4s_<version>_amd64.deb (requires dpkg-deb).
   Desktop file: export/p4s.desktop. Not a substitute for playtesting the
   binary on the Pentium 7505 first.

6. Windows / Mac
   A Windows x86_64 stub is in export_presets.cfg. Mac/Windows installers
   are later targets; this pass is optimisation + a working Linux preset.
