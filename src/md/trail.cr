module Md
  # The trail of files left, which File → Previous File and Next File
  # retrace (`app_links.cr`): a browser's back and forward stacks, of places
  # (`App::Place`). A window has one of its own; linked windows share their
  # link's (`ViewLink`), so Previous File in either goes where the group
  # came from.
  class Trail
    # The places Previous File goes back to, the last left last.
    getter back = [] of App::Place
    # The places Next File goes forward to again, the last undone last.
    getter forward = [] of App::Place

    def initialize
    end

    def initialize(@back : Array(App::Place), @forward : Array(App::Place))
    end

    # A trail with the same places, to go on apart from this one (linked
    # windows becoming separate each keep a copy).
    def dup : Trail
      Trail.new @back.dup, @forward.dup
    end
  end
end
