# frozen_string_literal: true

module LockingJobHelpers
  extend T::Sig

  sig { params(job_classes: Class).void }
  def clear_job_locks(*job_classes)
    # Iterate through all matching keys and delete them
    job_class_names = job_classes.uniq.map { |job_class| job_class.name.demodulize }
    job_class_names.each do |match|
      Dependabot.redis.scan_each(match: "*#{match}*") do |key|
        Dependabot.redis.del(key)
      end
    end
  end
end
