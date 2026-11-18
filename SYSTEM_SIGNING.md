# Signing bitFocus with the DriftVaneOS platform key

Goal: install and update bitFocus as a system app, so Android's Restricted Settings never blocks it and updates install with no prompt.

## 1. Get your platform key files
You need the pair your ROM is signed with (these are the files used for `platform` in your build's security folder):
- `platform.pk8`
- `platform.x509.pem`

Never commit them. Keep them out of the repo.

## 2. Add them as GitHub secrets
```
base64 -w0 platform.pk8       # copy output into secret PLATFORM_PK8_BASE64
base64 -w0 platform.x509.pem  # copy output into secret PLATFORM_X509_BASE64
```
Repo > Settings > Secrets and variables > Actions > New repository secret.

## 3. Push
The workflow builds two files per release:
- `bitFocus.apk`: normal build, no system UID, installs anywhere.
- `bitFocus-system.apk`: `android:sharedUserId="android.uid.system"` injected at build time and re-signed with your platform key.

The flag is injected only in CI because an APK that declares the system UID refuses to install on any phone that does not have the matching platform key (INSTALL_FAILED_SHARED_USER_INCOMPATIBLE).

## 4. Install on the DriftVaneOS phone
1. Uninstall any existing bitFocus first. Changing a package's UID cannot be done as an update.
2. Install `bitFocus-system.apk`.
3. The in-app updater detects uid 1000, downloads the `-system` asset from GitHub Releases and installs it through PackageInstaller with no prompt.

## Notes
- If you bake the APK into the ROM in `priv-app`, add a privapp-permissions XML that allows `android.permission.INSTALL_PACKAGES`.
- Newer Android versions deprecate sharedUserId. It still works for platform-signed apps on most ROMs, but test on your Pixel 10 build.
- Restricted Settings exemption for system-signed apps is the expected behaviour, but I could not test it on your ROM. If notification access still shows as restricted, grant it once in Settings.
