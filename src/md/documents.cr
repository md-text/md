module Md
  # The documents open in the process (Qt Creator's `DocumentModel`): one
  # `Document` per file, however many windows show it, so a window opening
  # a file another window has open joins that window's document, unsaved
  # edits and all, instead of reading a second copy from disk.
  #
  # A file is known by its key (`.key_for`): the canonical path —
  # `File.realpath`, which resolves symlinks and, on macOS, gives an
  # existing file's name the case it has on disk — so `./README.md`, a
  # symlink to it and `readme.md` on a case-insensitive volume are one
  # document. A hard link has a path of its own and is caught by comparing
  # the files themselves (`.find`). A document without a name — a new one,
  # or standard input — has no key and is shared only by identity, through
  # Window → New.
  #
  # The registry also holds what is one per process rather than one per
  # window: the files backed up this session (`.backup`) and the names of
  # unnamed documents' recovery files (`.unnamed_recovery_name`).
  module Documents
    # Every document with a window on it, in the order they were first shown.
    class_getter all = [] of Document

    @@by_key = {} of String => Document

    # The keys of the files backed up this session (`FILE~`, `.backup`).
    class_getter backed_up = Set(String).new

    # The canonical key of *path*: the real path of an existing file; for a
    # file that does not exist yet, the real path of its directory joined
    # with its name as typed (or the expanded path, when the directory is not
    # there either). The key is for matching only — a document keeps the
    # path it was given for display and for writing.
    def self.key_for(path : String) : String
      path = File.expand_path path
      dir = File.dirname(path)
      if File.exists?(path)
        File.realpath path
      elsif Dir.exists?(dir)
        File.join File.realpath(dir), File.basename(path)
      else
        path
      end
    rescue File::Error
      path
    end

    # The open document of *path*, if any: the one with its key, or else the
    # one whose file is the same file (a hard link, a bind mount). Unnamed
    # and standard-input documents are never found by a path. A file that
    # cannot be looked at (a directory without search permission on its
    # way) matches by key only, and so does a document whose file cannot.
    def self.find(path : String) : Document?
      if held = @@by_key[key_for(path)]?
        return held
      end
      return unless info = file_info(path)
      @@all.find do |doc|
        (other = doc.source.path) && (other_info = file_info(other)) && info.same_file?(other_info)
      end
    end

    # *path*'s file, links followed, or nil when it is not there or cannot
    # be looked at (`File.info?` raises for the latter).
    private def self.file_info(path : String) : File::Info?
      File.info?(path, follow_symlinks: true)
    rescue File::Error
    end

    # Puts *doc* in the registry, from its first view (`Document#attach`).
    # It takes its key unless another document holds the key already (a
    # spec's second App built on the same path), which leaves it reachable
    # through its window only.
    def self.add(doc : Document) : Nil
      return if @@all.includes?(doc)
      @@all << doc
      if key = doc.key
        @@by_key[key] ||= doc
      end
    end

    # Takes *doc* out of the registry: its last view left.
    def self.forget(doc : Document) : Nil
      @@all.delete doc
      @@by_key.reject! { |_, held| held.same? doc }
    end

    # Moves *doc* from the key *old* to its current one: it was saved under
    # another name, or a new file was written for the first time (its real
    # path resolves now).
    def self.rekey(doc : Document, old : String?) : Nil
      @@by_key.delete(old) if old && @@by_key[old]?.try(&.same?(doc))
      if (key = doc.key) && @@all.includes?(doc)
        @@by_key[key] ||= doc
      end
    end

    # Copies *path* to `path~` before the first save of the session writes
    # it, once per file per process, when there is a file to keep. Returns
    # what went wrong, for the save's notice, or nil.
    def self.backup(path : String) : String?
      key = key_for path
      return if @@backed_up.includes?(key) || !File.exists?(path)
      @@backed_up << key
      File.copy path, "#{path}~"
      nil
    rescue ex : IO::Error
      "backup #{path}~ failed: #{Md.error_text(ex)}"
    end

    # A recovery file name for a document without a name, unique among the
    # documents open: `unnamed-<date>-<time>-<pid>.md`, with `-2`, `-3`…
    # for another document that took the name in the same second.
    def self.unnamed_recovery_name : String
      base = "unnamed-#{Time.local.to_s("%Y%m%d-%H%M%S")}-#{Process.pid}"
      name = "#{base}.md"
      n = 1
      while @@all.any? &.recovery_name_taken?(name)
        name = "#{base}-#{n += 1}.md"
      end
      name
    end

    # Forgets every document and backup, as a fresh process would have none,
    # and the windows are separate again: for specs.
    def self.reset : Nil
      @@all.clear
      @@by_key.clear
      @@backed_up.clear
      @@window_link = App::WindowLink::Separate
    end

    # How windows on one document behave (Window → Linking): the one value
    # for the process, which every window's setting follows.
    class_getter window_link : App::WindowLink = App::WindowLink::Separate

    # Makes *mode* how windows on one document behave, for every window, once
    # however many windows' settings report the change (*initiator*'s first;
    # the others' equal values return at once). Linking makes a group of
    # each document's windows, led by *initiator* when it is among them, else
    # by the window used last, else the first, which the others mirror at
    # once; separating lets each window go on from where it is, with its own
    # copy of the group's trail. Every window on a document shown in more
    # than one is told.
    def self.link_windows(mode : App::WindowLink, initiator : App? = nil) : Nil
      return if mode == @@window_link
      @@window_link = mode
      App.instances.each &.window_link=(mode)
      @@all.each do |doc|
        next if doc.views.empty?
        if mode.linked?
          leader = {initiator, App.last_active}.find { |app| app && doc.views.includes?(app) } || doc.views.first
          link = ViewLink.new(doc, leader, leader.own_trail)
          doc.views.each { |view| link.add view }
          doc.link = link
          link.publish leader
        else
          doc.link.try &.dissolve
        end
        # Vi Mode swaps between a Neovim per window and one per document.
        doc.views.each &.relink_vi
        doc.notify "Windows on #{doc.name} are #{mode.linked? ? "linked" : "separate"}" if doc.views.size > 1
      end
    end
  end
end
