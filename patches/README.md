# Kernel patches

Store patches in dependency order with a short explanation of their upstream
base and purpose. Do not copy complete proprietary vendor source drops here.

`kernel/0001-sched-guard-rt-pull-with-walt.patch` fixes an inconsistent guard
in the public OPPO source: the RT-pull helper accesses a WALT-only task field
even when the stock configuration disables `CONFIG_SCHED_WALT`. The patch uses
the same combined feature guard already present around that field's definition.

`kernel/0002-ion-include-healthinfo-declarations.patch` makes the public OPPO
ION driver include the declarations guarded by `OPLUS_FEATURE_HEALTHINFO`. The
same driver uses those declarations under that feature guard, while its
implementation is linked by the enabled `CONFIG_MTK_ION` path even when
`CONFIG_OPLUS_HEALTHINFO` is disabled.

`kernel/0003-sched-provide-slide-tunables-without-walt.patch`
provides the two disabled-by-default slide tunables referenced by OPPO scheduler
code when the stock RT7 configuration leaves WALT disabled. WALT builds retain
the original implementation and ownership.

`kernel/0004-rgbled-stub-disabled-oplus-healthinfo.patch` makes the MT6360 LED
health callback a no-op when its optional backing driver is disabled. This
avoids both an unresolved symbol and unsafe workqueue use without a probed
healthinfo device.

`kernel/0005-imgsensor-link-common-eeprom-service.patch` links the existing
common v1.1 EEPROM service into the MT6853 image-sensor build, matching the
calls made by the retained public GC5035 sensor source.

`modules/0001-audio-stub-disabled-sia-pa-controls.patch` supplies no-op control
stubs when the optional SIA speaker-amplifier driver is disabled. The common
MT6853 machine driver calls these helpers through OPPO feature code, while the
stock RT7 configuration leaves `CONFIG_SIA_PA_ALGO` disabled. Configurations
that enable the SIA driver continue to use its real implementation.

`modules/0002-audio-stub-disabled-sia-aux-init.patch` adds the matching no-op
machine-card initialization fallback when neither SIA implementation is
enabled. It returns success without registering a nonexistent amplifier.
