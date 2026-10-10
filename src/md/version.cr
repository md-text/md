module Md
  # The version is read from `shard.yml` at compile time so that it has a single
  # source of truth: bump it there (and in CHANGELOG.md) and tag the release.
  VERSION = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("version:"))["version:".size..].strip }}
end
