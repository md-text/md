module Md
  # The version is read from `shard.yml` at compile time so that it has a single
  # source of truth: bump it there (and in CHANGELOG.md) and tag the release.
  VERSION = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("version:"))["version:".size..].strip }}

  # The author, the first of `shard.yml`'s `authors`, and md's website, its
  # `repository`: what Help → About names beside the version.
  AUTHOR  = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("  - ")).strip[2..] }}
  WEBSITE = {{ read_file("#{__DIR__}/../../shard.yml").lines.find(&.starts_with?("repository:"))["repository:".size..].strip }}
end
