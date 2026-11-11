# frozen_string_literal: true

# Load all defined processors so ApplicationProcessor::descendants is reliable.
Dir[Rails.root.join("app/processors/**/*.rb")].sort.each do |file|
  require file unless file.include?("application_processor")
end

class ProcessorManager
  PROCESSORS = ApplicationProcessor.descendants.map do |processor_class|
    { processor_class.slug => processor_class }
  end.reduce(&:merge)

  def self.processor_slug_list
    ["all"] + PROCESSORS.keys
  end

  def self.processor_exists?(slug)
    return true if slug == "all"

    processor_slug_list.include? slug
  end

  def self.paused?(slug)
    if slug == "all"
      PROCESSORS.all? do |_, processor|
        processor.topic_paused?
      end
    else
      PROCESSORS.fetch(slug).topic_paused?
    end
  end

  def self.pause(slug)
    if slug == "all"
      PROCESSORS.each_value do |processor|
        Flipper.enable(processor.topic_pause_flag)
      end
    else
      Flipper.enable(PROCESSORS.fetch(slug).topic_pause_flag)
    end
  end

  def self.resume(slug)
    if slug == "all"
      PROCESSORS.each_value do |processor|
        Flipper.disable(processor.topic_pause_flag)
      end
    else
      Flipper.disable(PROCESSORS.fetch(slug).topic_pause_flag)
    end
  end

  def self.current_status
    PROCESSORS.map do |slug, processor|
      [slug, pause_presenter(processor.paused?)]
    end
  end

  def self.pause_presenter(state)
    state ? :paused : :processing
  end
end
