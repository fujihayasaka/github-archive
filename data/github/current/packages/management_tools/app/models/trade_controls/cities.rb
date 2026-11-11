# typed: strict
# frozen_string_literal: true

module TradeControls
  class Cities
    include LocationTraits

    name, alpha2, alpha3, * = UKRAINE_BRAINTREE_COUNTRY

    # country code => region code => city name
    UA_14_MAKIIVKA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Makiivka", region: { name: "Donetsk Oblast", code: "14" })
    UA_14_DONETSK = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Donetsk", region: { name: "Donetsk Oblast", code: "14" })
    UA_09_KADIYIVKA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Kadiyivka", region: { name: "Luhansk", code: "09" })
    UA_14_HORLIVKA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Horlivka", region: { name: "Donetsk Oblast", code: "14" })
    UA_09_PEREVALSK = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Pereval'sk", region: { name: "Luhansk", code: "09" })
    UA_09_ALCHEVSK = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Alchevs'k", region: { name: "Luhansk", code: "09" })
    UA_14_YASINOVATAYA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Yasinovataya", region: { name: "Donetsk Oblast", code: "14" })
    UA_14_CHYSTYAKOVE = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Chystyakove", region: { name: "Donetsk Oblast", code: "14" })
    UA_09_LUTUGINO = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Lutugino", region: { name: "Luhansk", code: "09" })
    UA_09_ANTRATSIT = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Antratsit", region: { name: "Luhansk", code: "09" })
    UA_09_ROVENKI = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Rovenki", region: { name: "Luhansk", code: "09" })
    UA_14_AMVROSIYIVKA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Amvrosiyivka", region: { name: "Donetsk Oblast", code: "14" })
    UA_09_BRYANKA = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Bryanka", region: { name: "Luhansk", code: "09" })
    UA_09_SVERDLOVSK = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Sverdlovs'k", region: { name: "Luhansk", code: "09" })
    UA_09_NOVOPSKOV = City.new(name: name, alpha2: alpha2, alpha3: alpha3, city: "Novopskov", region: { name: "Luhansk", code: "09" })

    HIGH_RISK_CITIES = T.let([
      UA_14_MAKIIVKA,
      UA_14_DONETSK,
      UA_14_HORLIVKA,
      UA_14_YASINOVATAYA,
      UA_14_CHYSTYAKOVE,
      UA_14_AMVROSIYIVKA,
      UA_09_KADIYIVKA,
      UA_09_PEREVALSK,
      UA_09_ALCHEVSK,
      UA_09_LUTUGINO,
      UA_09_ANTRATSIT,
      UA_09_ROVENKI,
      UA_09_BRYANKA,
      UA_09_SVERDLOVSK,
      UA_09_NOVOPSKOV
    ].freeze, T::Array[TradeControls::City])

    sig { returns(T::Array[T.nilable(String)]) }
    def high_risk_cities_downcase
      HIGH_RISK_CITIES.map(&:city).compact.map(&:downcase)
    end
  end
end
