# frozen_string_literal: true

class SimulatedPublicationCheck
  def self.should_run?(review)
    review.instance_of?(AdvisoryReview)
  end

  def self.execute_check(review:)
    publisher = Publisher.new(review)

    if publisher.simulate
      summary = "Publication was performed and rolled back successfully."
      CheckResult.new(status: "passed", title: "Success", summary: summary)
    else
      summary = publisher.errors.map { |e| "#{e.options[:message]}\n#{PP.pp(publisher.errors.details, +"").chomp}" }.join("\n")
      CheckResult.new(status: "failed", title: "Failure", summary: summary)
    end
  end
end
