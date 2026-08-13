<h1 align="center">Windows-kde System Tray</h1>

<p align="center">
  A Windows 11-style System Tray for KDE Plasma 6.
</p>

<p align="center">
  <a href="https://kde.org/plasma-desktop">
    <img src="https://img.shields.io/badge/Plasma_6-1D99F3?logo=kde&logoColor=white&style=flat-square" alt="KDE Plasma 6">
  </a>
  <a href="https://fedoraproject.org">
    <img src="https://img.shields.io/badge/Fedora-51A2DA?logo=fedora&logoColor=white&style=flat-square" alt="Fedora">
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/License-GPLv3-86dbce?style=flat-square" alt="License: GPLv3">
  </a>
</p>

<p align="center">
  <img
    width="400"
    alt="Windows Modern System Tray and Action Centre on KDE Plasma"
    src="https://github.com/user-attachments/assets/4f3f2d95-46ea-460a-a779-ecf9e808ae63"
  />
</p>

<br>

## ✨ Features

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>🖥️ Windows-style System Tray</h3>
      Network, Volume, and Battery docked into a compact, always-visible cluster next to the expander arrow.
    </td>
    <td width="50%" valign="top">
      <h3>🔔 Action Centre</h3>
      A dedicated Windows 11-inspired popup for system controls, separate from the Hidden Items tray popup.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <h3>🧩 Configurable Tiles</h3>
      Double-click and drag to reorder Quick Settings tiles. Your layout persists across sessions.
    </td>
    <td width="50%" valign="top">
      <h3>🎨 Matching Icons</h3>
      The bundled WindowsModern-WhiteSurApps theme rounds out the look.
    </td>
  </tr>
</table>

<br>

## 📦 Installation

### ⭐ Recommended — one-command install

```bash
curl -fsSL https://github.com/RaceConditionWinner/Kde-windows-system-tray/releases/latest/download/install.sh | bash
```

This automatically:

- downloads the prebuilt System Tray plugin and verifies it against SHA-256 checksums
- installs and activates the WindowsModern-WhiteSurApps icon theme
- replaces the stock System Tray on your panel, preserving its position
- reloads Plasma and verifies the install

It's safe to run more than once. Only the plugin-install step requires
administrator authentication via `pkexec`; the rest runs as your user.

### 🛠️ Manual installation

For other distros, or if you'd rather build from source.

1. Install build dependencies (Fedora shown; see [system-tray/BUILD.md](system-tray/BUILD.md) for Arch/Debian/Ubuntu):
   ```bash
   sudo dnf install gcc-c++ cmake extra-cmake-modules \
     qt6-qtbase-devel qt6-qtdeclarative-devel \
     kf6-kpackage-devel kf6-kconfig-devel kf6-ki18n-devel kf6-kcoreaddons-devel \
     kf6-kwindowsystem-devel kf6-kio-devel kf6-kiconthemes-devel \
     kf6-kitemmodels-devel kf6-kservice-devel kf6-kxmlgui-devel \
     kf6-kjobwidgets-devel kf6-kcmutils-devel \
     libplasma-devel plasma-workspace-devel plasma-workspace-libs
   ```
2. Clone this repository:
   ```bash
   git clone https://github.com/RaceConditionWinner/Kde-windows-system-tray.git
   cd Kde-windows-system-tray
   ```
3. Build and install:
   ```bash
   cd system-tray
   ./dev.sh
   ```
4. Add "System Tray (Windows Modern)" to your panel: right-click the panel → **Add or Manage Widgets…**
5. (Optional) Install the icon theme, still from inside `system-tray/`:
   ```bash
   cp -r ../windows-icon/WindowsModern-WhiteSurApps ~/.local/share/icons/
   ```
   then set it via System Settings → Colors & Themes → Icons.

The manual path builds from source and never touches your panel layout automatically.

<br>

## ✅ Requirements

- KDE Plasma 6
- **Fedora KDE Plasma 6, x86_64** — the only environment the prebuilt release is currently built and tested for. Other distributions should use [manual installation](#-manual-installation).

## 🗑️ Uninstall

```bash
curl -fsSL https://github.com/RaceConditionWinner/Kde-windows-system-tray/releases/latest/download/uninstall.sh | bash
```

Restores the stock System Tray in its original position, restores your
previous icon theme, and removes the Windows Modern plugin. Safe to run
more than once.

## 🧑‍💻 Development

Source code lives in [`system-tray/`](system-tray) — see
[`system-tray/BUILD.md`](system-tray/BUILD.md) for build dependencies and
development instructions. The icon theme is under
[`windows-icon/WindowsModern-WhiteSurApps/`](windows-icon/WindowsModern-WhiteSurApps).

<br>

## 🙌 Credits

This project builds upon: 

- [Jeysef/KDE-Windows-Modern](https://github.com/Jeysef/KDE-Windows-Modern) — the System Tray plugin in `system-tray/` is a modified fork of this, itself built on KDE's plasma-workspace System Tray
- [WhiteSur-icon-theme](https://github.com/vinceliuice/WhiteSur-icon-theme) — the icon theme is a derivative of this

Original source headers and applicable license notices are preserved in the project source files.

## 📄 License

GPL-3.0. See [LICENSE](LICENSE).
