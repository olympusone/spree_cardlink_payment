module SpreeCardlinkPayment
  VERSION = '1.1.0'.freeze

  module_function

  # Returns the version of the currently loaded SpreeCardlinkPayment as a
  # <tt>Gem::Version</tt>.
  def version
    Gem::Version.new VERSION
  end
end
