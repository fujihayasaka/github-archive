# source://fast_gettext//lib/fast_gettext/vendor/string.rb#66
class String
  include ::Comparable
  include ::MessagePack::CoreExt
  include ::JSON::Ext::Generator::GeneratorMethods::String
  extend ::JSON::Ext::Generator::GeneratorMethods::String::Extend

  # source://fast_gettext//lib/fast_gettext/vendor/string.rb#68
  def %(*args); end
end