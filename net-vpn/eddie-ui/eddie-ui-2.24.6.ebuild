# Copyright 2024 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2
# Ebuild author: Google DeepMind Antigravity (AI)

EAPI=8

DOTNET_PKG_PROJECTS=(
	src/App.CLI.Linux/App.CLI.Linux.net8.csproj
)

DOTNET_PKG_COMPAT=8.0
inherit dotnet-pkg mono-env desktop xdg-utils

DESCRIPTION="AirVPN client (Eddie) - VPN tunnel UI and CLI"
HOMEPAGE="https://eddie.website https://github.com/AirVPN/Eddie"

# Instructions to generate NUGETS:
# 1. Download the source tarball: https://github.com/AirVPN/Eddie/archive/2.24.6.tar.gz
# 2. Extract it.
# 3. Run 'gdmt restore --project src/App.CLI.Linux/App.CLI.Linux.net8.csproj' (requires dev-dotnet/gentoo-dotnet-maintainer-tools)
# 4. Paste the output NUGETS variable below.
NUGETS="
https://api.nuget.org/v3-flatcontainer/microsoft.csharp/4.7.0/microsoft.csharp.4.7.0.nupkg
https://api.nuget.org/v3-flatcontainer/microsoft.netcore.app.crossgen2.linux-x64/8.0.8/microsoft.netcore.app.crossgen2.linux-x64.8.0.8.nupkg
"

SRC_URI="https://github.com/AirVPN/Eddie/archive/${PV}.tar.gz -> ${P}.tar.gz
	${NUGETS}
"

LICENSE="GPL-3"
SLOT="0"
KEYWORDS="~amd64"

# Dependencies
# Mono for UI, Dotnet SDK for CLI build
DEPEND="
	dev-lang/mono
	net-vpn/openvpn
	net-misc/curl
	app-admin/sudo
	sys-auth/polkit
	x11-libs/libnotify
	dev-libs/libayatana-appindicator
"
RDEPEND="${DEPEND}"
BDEPEND="
	${DOTNET_PKG_BDEPEND}
	dev-dotnet/dotnet-sdk
	dev-lang/mono
	dev-util/desktop-file-utils
"

S="${WORKDIR}/Eddie-${PV}"

pkg_setup() {
	dotnet-pkg_pkg_setup
}

src_configure() {
	dotnet-pkg_src_configure
}

src_compile() {
	# 1. Build CLI using dotnet-pkg (Net8)
	dotnet-pkg_src_compile

	# 2. Build UI using msbuild (Mono/Net4.8)
	# Clean any potential previous build artifacts
	rm -rf src/Lib.Core/bin src/Lib.Core/obj src/Lib.Platform.Linux/bin src/Lib.Platform.Linux/obj
	
	export TERM=xterm
	
    # We use a specific simplified solution or build script approach from PKGBUILD logic
    # but invoked via standard msbuild
    local solution="src/App.Forms.Linux/App.Forms.Linux.sln"
    
    # Define constants used in PKGBUILD
    # platform=x64 is hardcoded in PKGBUILD for Linux
    # Fallback to xbuild since msbuild is not reliably available in standard Gentoo mono
    xbuild /p:Configuration=Release /p:Platform=x64 /t:Rebuild "${solution}" /p:DefineConstants="EDDIEMONO4LINUX" || die "UI Build failed"
}

src_install() {
	# 1. Install CLI
	dotnet-pkg_src_install

	# 2. Install UI
	# The PKGBUILD uses a postbuild script, but we can just grab the binaries.
	# Location: src/App.Forms.Linux/bin/x64/Release/
	
	insinto /usr/lib/eddie-ui
	doins -r src/App.Forms.Linux/bin/x64/Release/*

	# Create wrapper for UI
	# We avoid mkbundle and use system mono
	# We must pass the resource path explicitly as we installed them to /usr/share
	# We also cd to the lib directory so it finds local DLLs easily
	cat > eddie-ui <<EOF
#!/bin/sh
cd /usr/lib/eddie-ui
exec mono /usr/lib/eddie-ui/App.Forms.Linux.exe --path.resources="/usr/share/eddie-ui" "\$@"
EOF
	dobin eddie-ui

	# Install native library built by Dotnet component
	# It usually ends up in the directory configured by dotnet-pkg
	# Based on logs: /var/tmp/portage/net-vpn/eddie-ui-2.24.6/work/eddie-ui-2.24.6_net8.0_Release/
	insinto /usr/lib/eddie-ui
	doins "${WORKDIR}/${P}_net8.0_Release/libLib.Platform.Linux.Native.so"

	# Install elevation helpers (Missing from previous step)
	exeinto /usr/lib/eddie-ui
	doexe "${WORKDIR}/${P}_net8.0_Release/eddie-cli-elevated"
	doexe "${WORKDIR}/${P}_net8.0_Release/eddie-cli-elevated-service"

	# 3. Resources and Icons (adapted from PKGBUILD)
	insinto /usr/share/eddie-ui
	doins resources/eddie-vpn.txt
	doins resources/manifest.json
	doins resources/libraries.txt
	doins resources/gpl3.txt
	doins resources/cacert.pem
	doins resources/iso-3166.json
	doins -r resources/lang
	doins -r resources/icons
	doins -r resources/providers

	# Desktop entry
	# PKGBUILD installs from bundle, we can use the one in repo if available or desktop-file-utils
	# The PKGBUILD copies from repository/linux_arch/bundle/...
	# Let's check if we can just assume standard locations or create one.
	# For safety, we'll try to use the one from the source if it exists reliably, 
	# otherwise we might need to craft one.
	# Checking source tree... repository/linux_arch/bundle/eddie-ui/usr/share/applications/eddie-ui.desktop seems to be the path.
	
	domenu repository/linux_arch/bundle/eddie-ui/usr/share/applications/eddie-ui.desktop
	
	# Pixmap
	insinto /usr/share/pixmaps
	doins repository/linux_arch/bundle/eddie-ui/usr/share/pixmaps/eddie-ui.png

	# Polkit
	insinto /usr/share/polkit-1/actions
	doins repository/linux_arch/bundle/eddie-ui/usr/share/polkit-1/actions/org.airvpn.eddie.ui.elevated.policy

}

pkg_postinst() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}

pkg_postrm() {
	xdg_desktop_database_update
	xdg_icon_cache_update
}
