module Md
  class App
    # File → Export as HTML… and Export as Text…: the document rendered to a
    # file, as `md --export` prints it (`Export.render`) — an HTML body
    # fragment, or the viewer's text without its styling — for the text as
    # it is now, saved or not. Both formats the command line has are
    # offered: HTML for a page, text for a mail or a terminal without md.
    #
    # The file is asked for as Save As asks (`#ask_text`, a leading `~`
    # being the home directory, `App.typed_path`), the document's name with
    # the format's extension filled in (nothing for a document without a
    # file), and written whole (`SaveFile`), over a file already there as
    # Save As writes, Qt Creator's export of a document being a save of a
    # copy. The document keeps its name, its file and its unsaved state; a
    # file open in md — the document's own source, most likely, by a name
    # typed with the wrong extension — is not written over, as the export
    # would replace the Markdown under the windows editing it.

    # The extension each format's file is named with by default.
    EXPORT_EXTENSIONS = {"html" => ".html", "text" => ".txt"}

    # Asks for the file to export the document to as *format* (one of
    # `Export::FORMATS`) and writes it (`#export`); a cancelled or empty
    # answer writes nothing.
    def export_prompt(format : String) : Nil
      ask_text("Export as #{format == "html" ? "HTML" : "text"} to: ", export_name(format)) do |answer|
        path = answer.try &.strip
        export(App.typed_path(path), format) if path && !path.empty?
      end
    end

    # Writes the document rendered as *format* to *path*, with a notice
    # either way; returns whether it was written. See the class comment.
    def export(path : String, format : String) : Bool
      if Documents.find(path)
        notice "Not exporting to #{path}: it is open in md"
        return false
      end
      SaveFile.write path, Export.render(@document.markdown, format)
      notice "Exported #{path}"
      true
    rescue ex : IO::Error
      notice "Cannot export #{path}: #{Md.error_text(ex)}"
      false
    end

    # The file name an export as *format* suggests: the document's file
    # with the format's extension in place of its own (`notes.md` →
    # `notes.html`), added when the name has that one already, or nothing
    # for a document without a file.
    private def export_name(format : String) : String
      return "" unless path = source.path
      extension = EXPORT_EXTENSIONS[format]
      name = "#{path.rchop(File.extname(path))}#{extension}"
      name == path ? "#{path}#{extension}" : name
    end
  end
end
