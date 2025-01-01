# typed: true
# frozen_string_literal: true

require_relative "../fast_test_helper"

class Localization::AcceptHeaderLocaleResolverTest < GitHub::TestCase
  def setup
    enable_feature_flag(:pt_br_homepage_translation)
    enable_feature_flag(:ko_homepage_translation)
  end

  def resolve(header)
    Localization::AcceptHeaderLocaleResolver.new.resolve(header)
  end

  test "returns default locale when header is nil" do
    assert_equal "en-US", resolve(nil)
  end

  test "returns default locale when header is *" do
    assert_equal "en-US", resolve("*")
  end

  test "returns the higher priority language served at GitHub" do
    assert_equal "pt-BR", resolve("de-DE,en-US;q=0.4,pt-BR;q=0.5")
  end

  test "returns the primary language, if served at GitHub" do
    assert_equal "pt-BR", resolve("pt-BR,en-US;q=0.4")
  end

  test "returns ko as primary language, if served at GitHub" do
    assert_equal "ko-KR", resolve("ko-KR,en-US;q=0.4")
  end

  test "handles a variety of real-world values" do
    samples = [
      "*",
      "bg-CZ,bg;q=0.9,en-CZ;q=0.8,en;q=0.7,cs-BG;q=0.6,cs;q=0.5,en-US;q=0.4,de;q=0.3",
      "ca,en;q=0.9,es;q=0.8,fr;q=0.7",
      "ca-es",
      "cs",
      "cs-CZ,cs;q=0.9,en;q=0.8,sk;q=0.7",
      "de,en-US;q=0.7,en;q=0.3",
      "de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7",
      "de-DE,en-US;q=0.7,en;q=0.3",
      "de-DE,en-US;q=0.8",
      "de-DE,en-US;q=0.9",
      "de-de",
      "en",
      "en,en-US;q=0.9",
      "en,en-US;q=0.9,es;q=0.8",
      "en,en-US;q=0.9,it;q=0.8,nl;q=0.7,ur;q=0.6,fr;q=0.5",
      "en,es;q=0.8,en-US;q=0.6",
      "en,zh;q=0.1",
      "en-AU",
      "en-CA,en;q=0.9,es-CO;q=0.8,es;q=0.7,en-GB;q=0.6,en-US;q=0.5",
      "en-GB",
      "en-GB,en-US;q=0.9,en;q=0.8",
      "en-GB,en-US;q=0.9,en;q=0.8,fr;q=0.7",
      "en-GB,en-US;q=0.9,en;q=0.8,hi;q=0.7",
      "en-GB,en-US;q=0.9,en;q=0.8,nl;q=0.7,es;q=0.6",
      "en-GB,en-US;q=0.9,en;q=0.8,pt;q=0.7",
      "en-GB,en-US;q=0.9,en;q=0.8,zh-TW;q=0.7,zh;q=0.6",
      "en-GB,en;q=0.5",
      "en-GB,en;q=0.9",
      "en-GB,en;q=0.9,ar-DZ;q=0.8,ar;q=0.7,fr-DZ;q=0.6,fr;q=0.5,en-US;q=0.4",
      "en-GB,en;q=0.9,ar-LB;q=0.8,ar;q=0.7,en-US;q=0.6",
      "en-GB,en;q=0.9,en-US;q=0.8",
      "en-GB,en;q=0.9,en-US;q=0.8,ar;q=0.7",
      "en-GB,en;q=0.9,en-US;q=0.8,ms;q=0.7",
      "en-GB,en;q=0.9,en-US;q=0.8,ro;q=0.7",
      "en-GB,en;q=0.9,en-US;q=0.8,ro;q=0.7,co;q=0.6",
      "en-GB,en;q=0.9,en-US;q=0.8,ur;q=0.7",
      "en-IN,en-US;q=0.9",
      "en-IN,en;q=0.9,en-GB;q=0.8,en-US;q=0.7,hi;q=0.6",
      "en-JM,en-GB;q=0.9,en-US;q=0.8,en;q=0.7",
      "en-PH,en-US;q=0.9,en;q=0.8",
      "en-US",
      "en-US,*",
      "en-US,en",
      "en-US,en-GB;q=0.7,fa-IR;q=0.3",
      "en-US,en-GB;q=0.9,en;q=0.8,tr-TR;q=0.7,tr;q=0.6",
      "en-US,en;q=0.5",
      "en-US,en;q=0.8",
      "en-US,en;q=0.8,fr;q=0.6,ru;q=0.4",
      "en-US,en;q=0.9",
      "en-US,en;q=0.9,ar;q=0.8",
      "en-US,en;q=0.9,de;q=0.8",
      "en-US,en;q=0.9,de;q=0.8,es;q=0.7,fr;q=0.6,he;q=0.5",
      "en-US,en;q=0.9,en-AU;q=0.8",
      "en-US,en;q=0.9,en-GB;q=0.8,it;q=0.7",
      "en-US,en;q=0.9,es-419;q=0.8,es;q=0.7",
      "en-US,en;q=0.9,es-US;q=0.8,es;q=0.7,fr-FR;q=0.6,fr;q=0.5",
      "en-US,en;q=0.9,es;q=0.8",
      "en-US,en;q=0.9,es;q=0.8,es-419;q=0.7,es-ES;q=0.6,pt;q=0.5,pt-BR;q=0.4,pt-PT;q=0.3,en-AU;q=0.2,en-GB;q=0.1,ru;q=0.1,fr;q=0.1,fr-CA;q=0.1,fr-FR;q=0.1,de;q=0.1,de-AT;q=0.1,de-DE;q=0.1,de-CH;q=0.1,nl;q=0.1,nl-BE;q=0.1,tr;q=0.1",
      "en-US,en;q=0.9,es;q=0.8,fr;q=0.7",
      "en-US,en;q=0.9,es;q=0.9",
      "en-US,en;q=0.9,fa;q=0.8",
      "en-US,en;q=0.9,fr-FR;q=0.8,fr;q=0.7",
      "en-US,en;q=0.9,fr;q=0.8",
      "en-US,en;q=0.9,he;q=0.8",
      "en-US,en;q=0.9,hr;q=0.8",
      "en-US,en;q=0.9,ht;q=0.8",
      "en-US,en;q=0.9,hy;q=0.8,ca;q=0.7",
      "en-US,en;q=0.9,ja;q=0.8",
      "en-US,en;q=0.9,ko;q=0.8",
      "en-US,en;q=0.9,pl;q=0.8",
      "en-US,en;q=0.9,pt;q=0.8,es;q=0.7,it;q=0.6,ca;q=0.5,fr;q=0.4,pl;q=0.3,hr;q=0.2,ro;q=0.1,eo;q=0.1,gl;q=0.1,cy;q=0.1,cs;q=0.1,ru;q=0.1,el;q=0.1,ja;q=0.1,ko;q=0.1,zh;q=0.1,bg;q=0.1,mk;q=0.1,af;q=0.1,da;q=0.1,nl;q=0.1,en-AU;q=0.1,en-CA;q=0.1,en-IN;q=0.1,en-NZ;q=0.1,en-ZA;q=0.1,en-GB;q=0.1,et;q=0.1,fil;q=0.1,fi;q=0.1,fr-CA;q=0.1,fr-CH;q=0.1,fr-FR;q=0.1,de;q=0.1,de-AT;q=0.1,de-DE;q=0.1,de-LI;q=0.1,de-CH;q=0.1,ka;q=0.1,gu;q=0.1,bn;q=0.1,ar;q=0.1,he;q=0.1,haw;q=0.1,hi;q=0.1,hu;q=0.1,is;q=0.1,id;q=0.1,ga;q=0.1,it-IT;q=0.1,it-CH;q=0.1,lv;q=0.1,lt;q=0.1,no;q=0.1,nb;q=0.1,nn;q=0.1,pt-BR;q=0.1,pt-PT;q=0.1,mo;q=0.1,sr;q=0.1,sk;q=0.1,sl;q=0.1,es-AR;q=0.1,es-CL;q=0.1,es-CO;q=0.1,es-CR;q=0.1,es-HN;q=0.1,es-419;q=0.1,es-MX;q=0.1,es-PE;q=0.1,es-ES;q=0.1,es-US;q=0.1,es-UY;q=0.1,es-VE;q=0.1,sv;q=0.1,ta;q=0.1,te;q=0.1,th;q=0.1,tr;q=0.1,uk;q=0.1,vi;q=0.1",
      "en-US,en;q=0.9,ro-RO;q=0.8,ro;q=0.7",
      "en-US,en;q=0.9,ru;q=0.8,ja;q=0.7,vi;q=0.6",
      "en-US,en;q=0.9,sl;q=0.8,hr;q=0.7,sr;q=0.6,de;q=0.5",
      "en-US,en;q=0.9,sv;q=0.8",
      "en-US,en;q=0.9,vi-VN;q=0.8,vi;q=0.7",
      "en-US,en;q=0.9,zh-CN;q=0.8,zh-TW;q=0.7,zh;q=0.6",
      "en-US,en;q=0.9,zh-TW;q=0.8,zh;q=0.7",
      "en-US,en;q=0.90",
      "en-US,pt-BR;q=0.5",
      "en-US,zh-CN;q=0.8,zh;q=0.7,zh-TW;q=0.5,zh-HK;q=0.3,en;q=0.2",
      "en-US;q=0.9, en;q=0.8",
      "en-au",
      "en-ca",
      "en-gb",
      "en-gb,en;q=0.5",
      "en-us",
      "en-us,en-gb,en;q=0.7,*;q=0.3",
      "en-us,en;q=0.5",
      "en;q=0.9,*;q=0.1",
      "es,en;q=0.8,zh;q=0.1",
      "es,es-419;q=0.9",
      "es-ES,es;q=0.9,en;q=0.8",
      "es-ES,es;q=0.9,en;q=0.8,de;q=0.7",
      "es-es",
      "fr-CA,fr;q=0.9,en-CA;q=0.8,en;q=0.7",
      "fr-FR",
      "fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7",
      "it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7",
      "ja,en",
      "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
      "ko,ko-KR;q=0.9,en-US;q=0.8,en;q=0.7",
      "nl-NL,en-GB;q=0.7,pl-PL;q=0.3",
      "nl-NL,nl;q=0.9,en-US;q=0.8,en;q=0.7",
      "pl-PL,pl;q=0.9,en-US;q=0.8,en;q=0.7",
      "pt-BR,pt;q=0.8,en-US;q=0.5,en;q=0.3",
      "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7",
      "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7,es-US;q=0.6,es;q=0.5,fr-FR;q=0.4,fr;q=0.3",
      "pt-BR,pt;q=0.9,en-US;q=0.8,en;q=0.7,zh;q=0.6",
      "ru",
      "ru, uk;q=0.8, be;q=0.8, en;q=0.7, *;q=0.01",
      "ru-RU,ru;q=0.8,en-US;q=0.5,en;q=0.3",
      "ru-RU,ru;q=0.9,en-GB;q=0.8,en;q=0.7",
      "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
      "sl-SI,sl;q=0.9,en-GB;q=0.8,en;q=0.7",
      "sr-RS,sr;q=0.9,en-US;q=0.8,en;q=0.7",
      "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
      "zh-CN,zh;q=0.8,en-US;q=0.5,en;q=0.3",
      "zh-CN,zh;q=0.9",
      "zh-CN,zh;q=0.9,en;q=0.8,zh-TW;q=0.7"
    ]
    actual = samples.map { |sample| resolve(sample) }.map(&:downcase).uniq.sort
    expected = %w[en-us pt-br ko ko-kr ja].sort
    assert_equal expected, actual
  end
end
