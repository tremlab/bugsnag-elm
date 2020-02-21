#!/usr/bin/env sh

version_in_elm_package_json=$(cat elm.json | jq -M .version)
version_in_internal=$(cat src/Bugsnag.elm | pcregrep -M "bugsnagElmVersion =\n    $version_in_elm_package_json" | grep $version_in_elm_package_json | tr -d '[:space:]')


if [ "${version_in_elm_package_json}" != "${version_in_internal}" ]; then
    echo "The value specified in Bugsnag.elm is not the same as the package version in elm.json. Please update it before publishing!"
    exit 1
else
    echo "Bugsnag.bugsnagElmVersion matches version in elm.json"
    exit 0
fi
