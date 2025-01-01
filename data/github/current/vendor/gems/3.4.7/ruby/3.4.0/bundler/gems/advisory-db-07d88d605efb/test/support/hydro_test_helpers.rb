# frozen_string_literal: true

module HydroTestHelpers
  def hydro_messages
    AdvisoryDB.hydro_publisher.sink.messages.map do |message|
      Hydro::Decoding::ProtobufDecoder.decode(message.data).message
    end
  end

  def expect_hydro_publish_error_stat_for(class_name)
    AdvisoryDB.hydro_publisher.stubs(:publish).returns(Hydro::Sink::Result.failure("womp womp"))
    AdvisoryDB.stats.stubs(:increment) # allows other unrelated calls
    AdvisoryDB.stats.expects(:increment).once.with("hydro.publish_error", tags: AdvisoryDB.dogtags(class: class_name.to_s))
  end
end

module ActiveSupport
  class TestCase
    include HydroTestHelpers
  end
end
