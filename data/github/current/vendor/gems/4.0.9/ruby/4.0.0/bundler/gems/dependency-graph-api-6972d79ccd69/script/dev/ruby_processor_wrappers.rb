def handle_development_processor_errors(block)
  require "rainbow"
  try_one_more_time = false
  (0..1).each do |i|
    begin
      begin
        block.call
      rescue => ex
        if ex.cause.is_a?(Hydro::KafkaSource::NoMatchingTopicsError)
          DependencyGraph.logger.info Rainbow("Kafka is functioning, but your topic isn't present! Check the docker-compose file and look for the KAFKA_CREATE_TOPICS entry, and make sure your topic is there.").red
          if i == 0
            # This code would ideally be standalone / dotcom hybrid aware. kcat doesn't work against the wurstmeister/kafka image,
            #  so we shouldn't try to run kcat in that situation, but doing it isn't the end of the world "for now".
            ex.message.match(/topics matching "(.*)"/) do |m|
              kcat_string = "kcat -b localhost -C -t" + m.captures[0]
              DependencyGraph.logger.info Rainbow("Trying to create kafka topic using kcat (should only work on dotcom kafka): " + kcat_string).yellow
              system(kcat_string)
              try_one_more_time = true
            end
          end
        elsif ex.cause.is_a?(Kafka::ConnectionError)
          DependencyGraph.logger.info Rainbow("It appears that your kafka service isn't up and running. You might need to `docker compose up`!").red
        end
        raise ex
      end
    # in development we'll retry standard errors if we have a recovery plan
    rescue StandardError => terminating_ex
      raise terminating_ex unless try_one_more_time
    end
  end
end
