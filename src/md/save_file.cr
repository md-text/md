module Md
  # Writes a file whole or not at all, as `QSaveFile` does: the text goes to
  # a temporary file beside the target, is flushed to disk, and is renamed
  # over the target, so a full disk or a crash mid-write leaves the previous
  # contents in place. The new file keeps the old one's permissions, owner
  # and group; a symbolic link is followed and its target written, the link
  # left a link.
  #
  # Where a rename cannot keep the file what it was, the text is written in
  # place instead (`QSaveFile::setDirectWriteFallback`): a target with other
  # hard links, which a rename would part from them; one that is not a
  # regular file; one whose owner or group cannot be given to a new file; and
  # a directory md may not create files in, though the file itself is
  # writable.
  module SaveFile
    # How many links `.target` follows before it takes the path as it is.
    MAX_LINKS = 40

    # Writes *text* to *path* (see the module comment). Raises `IO::Error`
    # (`File::Error`) as `File.write` does, the target unchanged when it is
    # not written in place; a target that is there and not writable is a
    # `File::AccessDeniedError`, as for `File.write`, rather than replaced.
    def self.write(path : String, text : String) : Nil
      target = target(path)
      # A new file is written where it goes: there is nothing before it to
      # keep, and it gets the permissions any new file does.
      return write_in_place(target, text) unless info = File.info?(target)
      unless File::Info.writable?(target)
        raise File::Error.from_os_error("Cannot write file", Errno::EACCES, file: target)
      end
      return write_in_place(target, text) unless info.file? && single_link?(target)
      begin
        # A fresh name, readable by md alone until it takes the target's
        # permissions.
        file = File.tempfile(".#{File.basename(target)}.", ".tmp", dir: File.dirname(target))
      rescue File::AccessDeniedError
        return write_in_place(target, text)
      end
      begin
        begin
          made = File.info(file.path)
          unless made.owner_id == info.owner_id && made.group_id == info.group_id
            File.chown file.path, info.owner_id.to_i, info.group_id.to_i
          end
          File.chmod file.path, info.permissions
        rescue File::Error
          file.delete
          file.close
          return write_in_place(target, text)
        end
        file.print text
        file.fsync
        file.close
        File.rename file.path, target
      rescue ex : IO::Error
        file.close rescue nil # the text it still holds failed to go once
        File.delete? file.path
        raise ex
      end
    end

    # The file *path* names: the end of its chain of symbolic links, which
    # need not exist yet (a link to a file still to be made).
    def self.target(path : String) : String
      MAX_LINKS.times do
        return path unless File.symlink?(path)
        link = File.readlink(path)
        path = Path[link].absolute? ? link : (Path[path].parent / link).to_s
      end
      path
    end

    private def self.write_in_place(path : String, text : String) : Nil
      File.open(path, "w") do |file|
        file.print text
        file.fsync
      end
    end

    # Whether the file at *path* has no other hard link.
    private def self.single_link?(path : String) : Bool
      LibC.stat(path.check_no_null_byte, out stat) != 0 || stat.st_nlink <= 1
    end
  end

  # What went wrong in *ex*, for a notice that names the file itself: the
  # OS's words alone ("Permission denied"), since a `File::Error`'s message
  # repeats the path ("Error opening file with mode 'w': 'PATH': …").
  def self.error_text(ex : IO::Error) : String
    ex.os_error.try(&.message) || ex.message || ex.class.name
  end
end
