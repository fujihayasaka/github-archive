# frozen_string_literal: true

module FormatterOverrides
  # We skip examples when they are unsuitable to the current environment
  # Ex: an example marked as `:cloud` will be skipped in `enterprise` mode
  def example_pending(notification)
    super unless notification.example.metadata[:skip]
  end

  def dump_pending(_); end
end
