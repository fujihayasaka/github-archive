# typed: false
# frozen_string_literal: true

module GitHub
  module Config
    module Octocat
      def octocat(text = nil)
        text = random_zen if text.blank?
        balloontop    = "_" * text.size
        spaces        = " " * text.size
        balloonbottom = "_" * [(text.size - 2), 0].max

        "
               MMM.           .MMM
               MMMMMMMMMMMMMMMMMMM
               MMMMMMMMMMMMMMMMMMM      _"    + balloontop    + "_
              MMMMMMMMMMMMMMMMMMMMM    | "    + spaces        + " |
             MMMMMMMMMMMMMMMMMMMMMMM   | "    + text          + " |
            MMMMMMMMMMMMMMMMMMMMMMMM   |_   " + balloonbottom + "|
            MMMM::- -:::::::- -::MMMM    |/
             MM~:~ 00~:::::~ 00~:~MM
        .. MMMMM::.00:::+:::.00::MMMMM ..
              .MM::::: ._. :::::MM.
                 MMMM;:::::;MMMM
          -MM        MMMMMMM
          ^  M+     MMMMMMMMM
              MMMMMMM MM MM MM
                   MM MM MM MM
                   MM MM MM MM
                .~~MM~MM~MM~MM~~.
             ~~~~MM:~MM~~~MM~:MM~~~~
            ~~~~~~==~==~~~==~==~~~~~~
             ~~~~~~==~==~==~==~~~~~~
                 :~==~==~==~==~~\n"
      end

      def zen
        puts ZEN_PHRASES.join("\n")
        "GitHub"
      end

      def random_zen
        ZEN_PHRASES.sample
      end

      ZEN_PHRASES = [
        "Responsive is better than fast.",
        "It's not fully shipped until it's fast.",
        "Accessible for all.",
        "Anything added dilutes everything else.",
        "Practicality beats purity.",
        "Approachable is better than simple.",
        "Mind your words, they are important.",
        "Speak like a human.",
        "Half measures are as bad as nothing at all.",
        "Encourage flow.",
        "Non-blocking is better than blocking.",
        "Favor focus over features.",
        "Avoid administrative distraction.",
        "Design for failure.",
        "Keep it logically awesome.",
      ]
    end
  end

  extend Config::Octocat
  OCTOCAT_CONTENT_TYPE = "application/octocat-stream".freeze
end
