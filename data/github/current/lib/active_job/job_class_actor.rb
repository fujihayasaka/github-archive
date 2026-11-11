# typed: true
# frozen_string_literal: true

# An actor representing a job class.
#
# The vexi_id includes the class name so it integrates with our feature flag
# actor storage and the internal GraphQL API.
class ActiveJob::JobClassActor
  include GitHub::VexiActor

  def self.find_by_id(id) # rubocop:disable GitHub/FindByDef
    new(id.to_s)
  end

  def initialize(job_class_name)
    @index_key = job_class_name
  end

  def vexi_id
    "#{self.class.name}:#{@index_key}"
  end
end
