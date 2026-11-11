# typed: true
# frozen_string_literal: true

class Actions::LargerRunners::LargerRunnersControllerStats
  attr_accessor :entity
  attr_reader :controller, :action, :method, :additional_tags

  def initialize(controller:, action:, method:, additional_tags: [])
    @controller = controller
    @action = action
    @method = method
    @additional_tags = additional_tags
  end

  def collect_metrics
    begin
      start = Time.now
      response = yield
    rescue => e # rubocop:todo Lint/RescueException
      GitHub.dogstats.distribution("#{name}.action.errors.dist", 1, tags: stats_tags.concat(["error:#{e.class.name}"]))
      raise e
    ensure
      GitHub.dogstats.distribution(
        "#{name}.duration",
        GitHub::Dogstats.duration(start),
        tags: stats_tags.concat(["success:#{response ? response.successful? : false}"])
      )
    end
  end

  private

  def name
    self.class.name&.underscore
  end

  def stats_tags
    return @_stats_tags if defined?(@_stats_tags)

    @_stats_tags = [
      "controller:#{controller}",
      "action:#{action}",
      "method:#{method}"
    ]

    @_stats_tags.concat(additional_tags) if additional_tags.present?
    @_stats_tags
  end
end
