# typed: strict
# frozen_string_literal: true
require "set"

module TradeControls
  # Represents a collection of sanctioned domain instances.
  class Domains

    RU_SANCTIONED_DOMAINS = T.let(%w(
      75arsenal.ru
      absolutbank.ru
      abuniversal.ru
      acuta.ru
      aerospace-systems.ru
      agrisovgaz.ru
      air-burg.ru
      akbars.ru
      alfabank.ru
      alfaleasing.ru
      alrosa.ru
      amelkin.msk.ru
      ao-star.ru
      aomrk.ru
      aq.ru
      aramid.ru
      arcticspg.ru
      argus-sfk.ru
      ase-ec.ru
      astracom.ru
      avtodor-tr.ru
      aziaship.ru
      azimp.ru
      azsco.ru
      baikalelectronics.ru
      baltinfocom.ru
      bazissoft.ru
      bitvan.ru
      bki-okb.ru
      blanc.ru
      bspb.ru
      ca-group.ru
      cbr.ru
      cetelem.ru
      ciam.ru
      ckb-rubin.ru
      compel.ru
      compressormash.ru
      cryogenmash.ru
      cscled.ru
      cvetmir3d.ru
      digispace.ru
      dmzdubna.ru
      dsol.ru
      e-streloy.ru
      ekos-1.ru
      elins.ru
      elpapiezo.ru
      epkgroup.ru
      eposignal.ru
      esphere.ru
      expobank.ru
      exportcenter.ru
      fgup-ohrana.ru
      fkpppz.ru
      frtk.ru
      gardatech.ru
      gazprom-auto.ru
      gazprom-neft.ru
      gazprombank.ru
      gidroagregat-nn.ru
      gle.ru
      goi.ru
      gribnaya-raduga.ru
      gstou.ru
      gubkin.ru
      gvgold.ru
      homecredit.ru
      in-vent.ru
      ioffe.ru
      ipfran.ru
      irkutskkabel.ru
      iss-reshetnev.ru
      issp.ac.ru
      iteranet.ru
      knc.ru
      komponenta.ru
      kraftway.ru
      kronshtadt.ru
      kryptonite.ru
      kupol.ru
      kzgroup.ru
      laggar-pro.ru
      laspace.ru
      lebedev.ru
      lockobank.ru
      lsystems.ru
      lveplant.ru
      macroems.ru
      mage.ru
      mcst.ru
      metallurgbank.ru
      metalmaster.ru
      mfisoft.ru
      mgri.ru
      milandr.ru
      mkb.ru
      mmzavod.ru
      mnsspb.ru
      module.ru
      mosinzhproekt.ru
      motor-invest.ru
      mpei.ru
      mts.ru
      mtsbank.ru
      newtowers.ru
      niiet.ru
      niihit.ru
      niitm.spb.ru
      niitp.ru
      nipigas.ru
      norsi-trans.ru
      novatek.ru
      npoelm.ru
      npp-istochnik.ru
      nppgamma.ru
      nskbl.ru
      nspcc.ru
      nzsip.ru
      nzslp.ru
      ocean.ru
      oktanta-ndt.ru
      omk.ru
      ooo-monitoring.ru
      open.ru
      optron-stavropol.ru
      osnovalab.ru
      ostec-group.ru
      pgups.ru
      phcloud.ru
      picaso-3d.ru
      pochtabank.ru
      podolskkabel.ru
      priusel.ru
      proletarsky.ru
      promreshenie.ru
      promtech-dubna.ru
      promtech-kazan.ru
      prosoft.ru
      psbank.ru
      pscb.ru
      ptkgroup.ru
      ptsecurity.ru
      radioavionica.ru
      rawenstvo.ru
      realexport.ru
      realloc.spb.ru
      rifcorp.ru
      rirt.ru
      rnt.ru
      rosatom.ru
      rosbank.ru
      rq.ru
      rqc.ru
      rsb.ru
      rshb.ru
      rt.ru
      rushydro.ru
      rusventure.ru
      rutarget.ru
      rvc.ru
      sber-solutions.ru
      sberbank-ast.ru
      sberbank-cib.ru
      sberbank.ru
      sbercloud.ru
      shipyard-yantar.ru
      shtormtech.ru
      signal-teplo.ru
      signaltec.ru
      signatec.ru
      sistema.ru
      skolkovo.ru
      skolkovotech.ru
      skoltech.ru
      smartlogister.ru
      sogaz.ru
      sovcombank.ru
      spacecorp.ru
      spbexchange.ru
      spectrumit.ru
      ssep.ru
      stanki.ru
      steerer.ru
      suek.ru
      sverdlova.ru
      svpz.ru
      symmetron.ru
      t-argos.ru
      temp-avia.ru
      tetis-pro.ru
      tinkoff.ru
      tkbbank.ru
      tmholding.ru
      touchin.ru
      tribit.ru
      tulamash.ru
      tulammo.ru
      tulatochmash.ru
      tvema.ru
      tverna.ru
      u-mac.ru
      ubrr.ru
      umpo.ru
      uralsib.ru
      vbf.ru
      velobike.ru
      vestabank.ru
      vniia.ru
      vniief.ru
      vostokwatch.ru
      vtb.ru
      vympel.ru
      vzavod.ru
      yarz.ru
      yoomoney.ru
      zenit.ru
      zid.ru
    ).freeze, T::Array[String])

    UA_SANCTIONED_DOMAINS = T.let(%w(
      pib.ua
      sbrf.com.ua
    ).freeze, T::Array[String])

    BY_SANCTIONED_DOMAINS = T.let(%w(
      agat.by
      amkodor.by
      avia407.by
      bankdabrabyt.by
      belavia.by
      belveb.by
      intechs.by
      kbradar.by
      mzkt.by
      uavheli.by
    ).freeze, T::Array[String])

    SY_SANCTIONED_DOMAINS = T.let(%w(
      dz-water.gov.sy
      hiast.edu.sy
      tishreen.edu.sy
    ).freeze, T::Array[String])

    AT_SANCTIONED_DOMAINS = T.let(%w(
      sberbank.at
    ).freeze, T::Array[String])

    EU_SANCTIONED_DOMAINS = T.let(%w(
      vtb.eu
    ).freeze, T::Array[String])

    VN_SANCTIONED_DOMAINS = T.let(%w(
      vtb.com.vn
    ).freeze, T::Array[String])

    TR_SANCTIONED_DOMAINS = T.let(%w(
      asbgroup.com.tr
      bosfor-avrasya.com.tr
      egetir.com.tr
      globusturkey.com.tr
      sistema.com.tr
    ).freeze, T::Array[String])

    SU_SANCTIONED_DOMAINS = T.let(%w(
      inp.nsk.su
      quarta.su
      vpv.su
    ).freeze, T::Array[String])

    DE_SANCTIONED_DOMAINS = T.let(%w(
      bentway.de
      kara-trading.de
    ).freeze, T::Array[String])

    ME_SANCTIONED_DOMAINS = T.let(%w(
      ideascup.me
    ).freeze, T::Array[String])

    AE_SANCTIONED_DOMAINS = T.let(%w(
      hamriyahsteel.ae
      ldscomtrade.ae
      skyparts.ae
    ).freeze, T::Array[String])

    IN_SANCTIONED_DOMAINS = T.let(%w(
      ron.in
    ).freeze, T::Array[String])

    RS_SANCTIONED_DOMAINS = T.let(%w(
      mci.rs
    ).freeze, T::Array[String])

    MV_SANCTIONED_DOMAINS = T.let(%w(
      vbbrothers.com.mv
    ).freeze, T::Array[String])

    CN_SANCTIONED_DOMAINS = T.let(%w(
      gt.cn
      jl1.cn
      rdscargo.ae.cn
    ).freeze, T::Array[String])

    RO_SANCTIONED_DOMAINS = T.let(%w(
      sistema.com.ro
    ).freeze, T::Array[String])

    BA_SANCTIONED_DOMAINS = T.let(%w(
      prointer.ba
      sirius2010.ba
    ).freeze, T::Array[String])

    BE_SANCTIONED_DOMAINS = T.let(%w(
      ett.be
    ).freeze, T::Array[String])

    PS_SANCTIONED_DOMAINS = T.let(%w(
      herzallah.ps
    ).freeze, T::Array[String])

    CH_SANCTIONED_DOMAINS = T.let(%w(
      thamestone.ch
    ).freeze, T::Array[String])

    KG_SANCTIONED_DOMAINS = T.let(%w(
      weitmann.kg
    ).freeze, T::Array[String])

    SG_SANCTIONED_DOMAINS = T.let(%w(
      microetech.sg
    ).freeze, T::Array[String])

    OTHER_SANCTIONED_DOMAINS = T.let(%w(
      acs-lc.com
      aithea.com
      alfabank.com
      ali2k.com
      aliabkar.com
      archlinux.us
      arttronix.com
      arvancloud.com
      arxfe.com
      avrorasystems.com
      baikalelectronics.com
      bigmir.net
      burevestnik.com
      cady-ic.com
      chinele.com
      chista.io
      cryptex.net
      deeppavlov.ai
      develoop.run
      digikala.com
      digitalenergy.online
      dimkt.net
      eledtrodetal.com
      elektrodetal.com
      farzambehboudi.com
      futurisfze.com
      gclogistics-me.com
      geoscan.aero
      greatsharelogistics.com
      gruzinov.com
      gsk-sd.com
      hasani.com
      highlandgold.com
      itbrk.com
      jarvisint.com
      jsc-energiya.com
      kartal-exim.com
      kismetcg.com
      kompaniets.dev
      lithium-element.com
      loqusgroup.com
      megasan.com
      morphbits.io
      mousavi.info
      multiclet.com
      nexign.com
      npzoptics.com
      ozkayaotomotiv.net
      peppersec.com
      polimerprom.com
      polyus.com
      presstv.com
      prom-ts.com
      promoil.com
      ptsecurity.com
      pumaenergy.com
      qubit.org
      radiocomp.net
      researchgroupnederland.com
      resolute-mt.com
      rhc.aero
      rusavtomatika.com
      sciprog.center
      sharif.edu
      shengcore-ic.com
      sinocnc.com
      status-it.com
      svyazservis.com
      swisstecag.com
      tensy.org
      tornado.cash
      turkikunion.com
      ubank.net
      ugmk.com
      umatex.com
      uniguajira.edu.co
      uralhelicom.com
      uralmash-ngo.com
      uu-ic.com
      velesstroy.com
      vtb.com
      vygon.consulting
      yadro.com
      zadna-int.com
      zrenergy.com
    ).freeze, T::Array[String])

    IR_SANCTIONED_DOMAINS = T.let(%w(
      agri-jahad.ir
      aliabkar.ir
      amnafzar.ir
      aut.ac.ir
      bahman.ir
      comp.iust.ac.ir
      email.kntu.ac.ir
      iran.ir
      isc.co.ir
      justice.ir
      mail.sbu.ac.ir
      mcth.ir
      medu.ir
      mod.ir
      modi.ir
      moi.ir
      mop.ir
      mrud.ir
      msrt.ir
      mut.ac.ir
      peykasa.ir
      peymanmajidi.ir
      rezamk.ir
      sahab.ir
      sbu.ac.ir
      ut.ac.ir
      vaja.ir
    ).freeze, T::Array[String])

    CU_SANCTIONED_DOMAINS = T.let(%w(
      agrinfor.cu
      avianet.cu
      ceniai.inf.cu
      cubadefensa.cu
      fishnavy.inf.cu
      hidro.cu
      infomed.sld.cu
      mfp.gov.cu
      mic.cu
      micons.cu
      min.cult.cu
      minint.gob.cu
      minjus.cu
      minrex.gob.cu
      parlamentocubano.gob.cu
      reduniv.edu.cu
      sime.co.cu
      tsp.gob.cu
    ).freeze, T::Array[String])

    IR_SANCTIONED_TLDS = T.let(%w(
      .gov.ir
    ).freeze, T::Array[String])

    CU_SANCTIONED_TLDS = T.let(%w(
      .gob.cu
    ).freeze, T::Array[String])

    SANCTIONED_DOMAINS = T.let(
      []
        .concat(AE_SANCTIONED_DOMAINS)
        .concat(AT_SANCTIONED_DOMAINS)
        .concat(BA_SANCTIONED_DOMAINS)
        .concat(BE_SANCTIONED_DOMAINS)
        .concat(BY_SANCTIONED_DOMAINS)
        .concat(CH_SANCTIONED_DOMAINS)
        .concat(CN_SANCTIONED_DOMAINS)
        .concat(CU_SANCTIONED_DOMAINS)
        .concat(DE_SANCTIONED_DOMAINS)
        .concat(EU_SANCTIONED_DOMAINS)
        .concat(IN_SANCTIONED_DOMAINS)
        .concat(IR_SANCTIONED_DOMAINS)
        .concat(KG_SANCTIONED_DOMAINS)
        .concat(ME_SANCTIONED_DOMAINS)
        .concat(MV_SANCTIONED_DOMAINS)
        .concat(OTHER_SANCTIONED_DOMAINS)
        .concat(PS_SANCTIONED_DOMAINS)
        .concat(RO_SANCTIONED_DOMAINS)
        .concat(RS_SANCTIONED_DOMAINS)
        .concat(RU_SANCTIONED_DOMAINS)
        .concat(SG_SANCTIONED_DOMAINS)
        .concat(SU_SANCTIONED_DOMAINS)
        .concat(SY_SANCTIONED_DOMAINS)
        .concat(TR_SANCTIONED_DOMAINS)
        .concat(UA_SANCTIONED_DOMAINS)
        .concat(VN_SANCTIONED_DOMAINS)
        .to_set.freeze, T::Set[String]
    )
    SANCTIONED_TLDS = T.let([].concat(IR_SANCTIONED_TLDS).concat(CU_SANCTIONED_TLDS).to_set.freeze, T::Set[String])

    sig { params(email: T.nilable(String)).returns(T::Boolean) }
    def self.sanctioned_email?(email)
      # organizations isn't required to set billing_emails, and as such email can be nil
      return false if email.blank?

      downcased_domain = email.split("@").last.to_s.strip.downcase
      return false if downcased_domain.blank?

      return true if SANCTIONED_DOMAINS.include?(downcased_domain)

      SANCTIONED_TLDS.any? { |d| downcased_domain.end_with?(d) }
    end
  end
end
