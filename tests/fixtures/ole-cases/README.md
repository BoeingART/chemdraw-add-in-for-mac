# Native preview fixtures

These hand-authored CDXML drawings exercise benzene; wedge/hash bonds, charge and isotope labels; Unicode reaction annotations; red/blue drawing objects; four structures across a 2 × 2 paper grid; content near the end of a 3 × 15 grid; 30 independent fragments; and an empty drawing.

`late-page-native.cdx` is derived from the repository's ethanol clipboard fixture: its object positions and bounds are translated to a later page, and the print grid is set to 3 × 15. It tests native CDX preview normalization separately from CDXML parsing. The default suite contains nine cases.

The color table starts with the default white background and black foreground. Explicit red and blue objects use indices 4 and 5 and the lowercase CDXML `color` attribute.

Run `zsh scripts/test-ole-preview-cases.sh` from the repository. The test uses the installed ChemDraw windowless renderer, compares the converted vector preview with its native PDF, and verifies that the input file is unchanged. It saves preview evidence under `build/ole-preview-cases/`. This check covers rendering; live Word/PowerPoint object identity and save acceptance use `scripts/test-ole-performance-live.sh` separately.
