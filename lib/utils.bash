#!/usr/bin/env bash

set -euo pipefail

GH_REPO="https://github.com/containers/podman"
TOOL_NAME="podman"
TOOL_TEST="podman --version"

fail() {
	echo -e "asdf-$TOOL_NAME: $*"
	exit 1
}

curl_opts=(-fsSL)

if [ -n "${GITHUB_API_TOKEN:-}" ]; then
	curl_opts=("${curl_opts[@]}" -H "Authorization: Bearer ${GITHUB_API_TOKEN}")
fi

sort_versions() {
	sed 'h; s/[+-]/./g; s/.p\([[:digit:]]\)/.z\1/; s/$/.z/; G; s/\n/ /' |
		LC_ALL=C sort -t. -k 1,1 -k 2,2n -k 3,3n -k 4,4n -k 5,5n | awk '{print $2}'
}

list_github_tags() {
	git ls-remote --tags --refs "$GH_REPO" |
		grep -o 'refs/tags/.*' | cut -d/ -f3- |
		sed 's/^v//' # NOTE: You might want to adapt this sed to remove non-version strings from tags
}

list_all_versions() {
	local releases_path next_link all_versions versions cmd_out

	releases_path=https://api.github.com/repos/containers/podman/releases

	next_link="${releases_path}?per_page=100&page=1"
	all_versions=""

	while [ -n "${next_link}" ]; do

		# Download releases page
		cmd_out=$(curl "${curl_opts[*]}" --verbose --retry 10 --retry-delay 2 -s "${next_link}" 2>&1)

		# Get versions
		versions=$(echo "${cmd_out}" | grep "\"tag_name\":" | sed 's/^ *"tag_name"\: *"v\?\(.*\)", *$/\1/')
		all_versions="${versions}\n${all_versions}"

		# Get next link
		next_link=$(echo "${cmd_out}" | grep '< link: ')

		if [[ ${next_link} == *'rel="next"'* ]]; then
			# shellcheck disable=SC2001
			next_link=$(echo "${next_link}" | sed 's/< link: <\(.*\)>; rel="next".*$/\1/')
			# shellcheck disable=SC2001
			next_link=$(echo "${next_link}" | sed 's/^.*<\(.*\)$/\1/')
		else
			next_link=""
		fi

	done

	echo "${all_versions}"
}

download_release() {
	local version filename url
	version="$1"
	filename="$2"

	# FIXME: Add support for other OS/ARCH combinations.
	url="$GH_REPO/releases/download/v${version}/podman-remote-static-linux_amd64.tar.gz"

	echo "* Downloading $TOOL_NAME release $version..."
	curl "${curl_opts[@]}" -L -s -o "$filename" -C - "$url" || fail "Could not download $url"
}

install_version() {
	local install_type="$1"
	local version="$2"
	local install_path="${3%/bin}/bin"

	if [ "$install_type" != "version" ]; then
		fail "asdf-$TOOL_NAME supports release installs only"
	fi

	(
		mkdir -p "$install_path"
		cp -r "$ASDF_DOWNLOAD_PATH"/* "$install_path"

		# TODO: Assert podman executable exists.
		local tool_cmd
		tool_cmd="$(echo "$TOOL_TEST" | cut -d' ' -f1)"
		test -x "$install_path/$tool_cmd" || fail "Expected $install_path/$tool_cmd to be executable."

		echo "$TOOL_NAME $version installation was successful!"
	) || (
		rm -rf "$install_path"
		fail "An error occurred while installing $TOOL_NAME $version."
	)
}
