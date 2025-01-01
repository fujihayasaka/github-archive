module Kernel
  alias_method :old_warn, :warn

  def self.warn(msg)
    # in production, we need these to get logged somewhere
    if Rails.env.production? || ENV["LOGGER_FOR_KERNEL_WARNINGS"] == "1"
      DependencyGraph.logger.warn("exception.message" => msg, "gh.exception.is_kernel_warning" => true)
    else
      # in development keep the output looking noticeable
      self.old_warn(msg)
    end
  end
end
