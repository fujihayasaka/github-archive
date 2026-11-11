# frozen_string_literal: true

# This handler can be used when testing deployments of new consumers or
# to move a topic offset forward without manipulating kafka directly.
class NoopHandler
  def self.run(_message)
    Rails.logger.info("#{self}: Hydro event dismissed.")
  end
end
