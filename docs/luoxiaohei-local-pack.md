# Luo Xiaohei Local Pack Notes

The local Luo Xiaohei pack is generated from a local checkout of
`https://github.com/jiang-taibai/IXiaoHei.git`, verified reachable at remote HEAD
`94d7eb55b85dcf10e47ad002d0417d0fb4d91436`.

The inspected upstream checkout contains `README.md` but no license file. Treat
the resulting frames as local-only test assets. Do not bundle, redistribute, or
publish these images without confirming rights from the original IP owner and
asset author.

`scripts/build-luoxiaohei-local-pack.py` now keeps one Focus Pet action per
distinct local animation group:

- `idle`: claw licking idle loop
- `distractedLook`: shake-head reminder
- `nudgeStrong`: watermelon reminder
- `welcomeBack`: bye/welcome animation
- `stretch`: play animation
- `breakRelax`: guitar/rest loop
- `run`: drumstick movement loop

Runtime-only states such as drag, landing, screen transfer, mouse summon, sleep,
breathing, and break end are resolved by Focus Pet fallback rules instead of
being duplicated in the generated manifest.
