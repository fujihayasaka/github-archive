# typed: true
# frozen_string_literal: true

class PiController < ApplicationController

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  # PI Day easter egg. Returns values, ASCII art, a special photo on March 14th.
  def index
    filename = "pi"

    respond_to do |format|
      format.html do
        if request.original_url.downcase.end_with?(".htm", ".html")
          redirect_to "/topics/calculating-pi"
        else
          render plain: <<~EOF

            3.141592653589793238462643383279
            5028841971693993751058209749445923
          07816406286208998628034825342117067
          9821    48086         5132
          823      06647        09384
        46        09550        58223
        17        25359        4081
                  2848         1117
                  4502         8410
                  2701         9385
                  21105        55964
                  46229        48954
                  9303         81964
                  4288         10975
                66593         34461
                284756         48233
                78678          31652        71
              2019091         456485       66
              9234603           48610454326648
            2133936            0726024914127
            3724587             00660631558
            817488               152092096

            Via https://github.com/Legend-of-iPhoenix/ascii-pi

            EOF
        end
      end

      format.jpeg do # show a pie photo every day of the year except Pi Day (March 14th)
        response.headers["pi_day"] = "false"

        if Time.now.strftime("%B %d") == "March 14"
          response.headers["pi_day"] = "true"
          filename = "pi-day"
        end

        File.open("public/pi/#{filename}.jpg") do |f|
          send_data f.read, type: "image/jpeg", disposition: "inline"
        end
      end

      format.png do # show a pie photo every day of the year except Pi Day (March 14th)
        response.headers["pi_day"] = "false"

        if Time.now.strftime("%B %d") == "March 14"
          response.headers["pi_day"] = "true"
          filename = "pi-day"
        end

        File.open("public/pi/#{filename}.png") do |f|
          send_data f.read, type: "image/png", disposition: "inline"
        end
      end

      format.json do
        render plain: <<~EOF
          {"pi":3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196442881097566593344612847564823378678316527120190914564856692346034861045432664821339360726024914127372458700660631}
        EOF
      end

      format.xml do
        render plain: <<~EOF
          <pi>3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196442881097566593344612847564823378678316527120190914564856692346034861045432664821339360726024914127372458700660631</pi>
        EOF
      end

      format.any :toml, :yaml do
        render plain: <<~EOF
          pi: 3.14159265358979323846264338327950288419716939937510582097494459230781640628620899862803482534211706798214808651328230664709384460955058223172535940812848111745028410270193852110555964462294895493038196442881097566593344612847564823378678316527120190914564856692346034861045432664821339360726024914127372458700660631
        EOF
      end
    end
  end
end
