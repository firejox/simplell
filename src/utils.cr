module Simplell
  struct EndMarker; end

  class SyntaxError < Exception
    def initialize(message = "")
      super("SyntaxError " + message)
    end
  end
end
