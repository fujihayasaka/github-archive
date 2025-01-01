# typed: strict
# frozen_string_literal: true
require "set"

module TradeControls
  # Represents a collection of sanctioned domain instances.
  class Domains
    extend T::Sig

    RU_SANCTIONED_DOMAINS = T.let(%w(
      absolutbank.ru
      acuta.ru
      air-burg.ru
      alfabank.ru
      alfaleasing.ru
      alrosa.ru
      akbars.ru
      amelkin.msk.ru
      ao-star.ru
      aq.ru
      aramid.ru
      arcticspg.ru
      argus-sfk.ru
      ase-ec.ru
      astracom.ru
      aerospace-systems.ru
      avtodor-tr.ru
      baikalelectronics.ru
      baltinfocom.ru
      bazissoft.ru
      bki-okb.ru
      blanc.ru
      bspb.ru
      ca-group.ru
      cbr.ru
      cetelem.ru
      ciam.ru
      ckb-rubin.ru
      compel.ru
      cryogenmash.ru
      dsol.ru
      ekos-1.ru
      elins.ru
      epkgroup.ru
      esphere.ru
      expobank.ru
      exportcenter.ru
      fgup-ohrana.ru
      frtk.ru
      gardatech.ru
      gazprom-auto.ru
      gazprom-neft.ru
      gazprombank.ru
      gle.ru
      gribnaya-raduga.ru
      gstou.ru
      gubkin.ru
      homecredit.ru
      ioffe.ru
      ipfran.ru
      iss-reshetnev.ru
      issp.ac.ru
      iteranet.ru
      jl1.cn
      knc.ru
      komponenta.ru
      kraftway.ru
      kryptonite.ru
      kronshtadt.ru
      kzgroup.ru
      laspace.ru
      lebedev.ru
      lockobank.ru
      lsystems.ru
      mage.ru
      mcst.ru
      mfisoft.ru
      milandr.ru
      mkb.ru
      mgri.ru
      mnsspb.ru
      module.ru
      mosinzhproekt.ru
      mpei.ru
      mts.ru
      mtsbank.ru
      niiet.ru
      niitm.spb.ru
      niitp.ru
      nipigas.ru
      norsi-trans.ru
      nppgamma.ru
      nskbl.ru
      nspcc.ru
      novatek.ru
      nzsip.ru
      ocean.ru
      oktanta-ndt.ru
      omk.ru
      open.ru
      osnovalab.ru
      ostec-group.ru
      pgups.ru
      picaso-3d.ru
      pochtabank.ru
      proletarsky.ru
      promreshenie.ru
      prosoft.ru
      psbank.ru
      pscb.ru
      ptsecurity.ru
      radioavionica.ru
      rawenstvo.ru
      realloc.spb.ru
      rirt.ru
      rnt.ru
      rosatom.ru
      rosbank.ru
      rq.ru
      rqc.ru
      rsb.ru
      rshb.ru
      rushydro.ru
      rusventure.ru
      rutarget.ru
      rvc.ru
      rt.ru
      sber-solutions.ru
      sberbank-ast.ru
      sberbank-cib.ru
      sberbank.ru
      sbercloud.ru
      shipyard-yantar.ru
      signatec.ru
      signal-teplo.ru
      signaltec.ru
      sistema.ru
      skolkovo.ru
      skolkovotech.ru
      skoltech.ru
      sogaz.ru
      sovcombank.ru
      spacecorp.ru
      spbexchange.ru
      shtormtech.ru
      stanki.ru
      suek.ru
      sverdlova.ru
      symmetron.ru
      temp-avia.ru
      tetis-pro.ru
      t-argos.ru
      tinkoff.ru
      tkbbank.ru
      tmholding.ru
      touchin.ru
      tribit.ru
      tulamash.ru
      tulammo.ru
      tverna.ru
      ubrr.ru
      umpo.ru
      uralsib.ru
      velobike.ru
      vestabank.ru
      vniia.ru
      vniief.ru
      vtb.ru
      vympel.ru
      vzavod.ru
      yoomoney.ru
      zenit.ru
      zid.ru
    ).freeze, T::Array[String])

    UA_SANCTIONED_DOMAINS = T.let(%w(
      pib.ua
      sbrf.com.ua
    ).freeze, T::Array[String])

    BY_SANCTIONED_DOMAINS = T.let(%w(
      amkodor.by
      avia407.by
      bankdabrabyt.by
      belavia.by
      belveb.by
      kbradar.by
      mzkt.by
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
      sistema.com.tr
    ).freeze, T::Array[String])

    SU_SANCTIONED_DOMAINS = T.let(%w(
      inp.nsk.su
      vpv.su
      quarta.su
    ).freeze, T::Array[String])

    PK_SANCTIONED_DOMAINS = T.let(%w(
      nu.edu.pk
    ).freeze, T::Array[String])

    DE_SANCTIONED_DOMAINS = T.let(%w(
      bentway.de
    ).freeze, T::Array[String])

    ME_SANCTIONED_DOMAINS = T.let(%w(
      ideascup.me
    ).freeze, T::Array[String])

    MX_SANCTIONED_DOMAINS = T.let(%w(
      bisoft.com.mx
    ).freeze, T::Array[String])

    AE_SANCTIONED_DOMAINS = T.let(%w(
      hamriyahsteel.ae
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
    ).freeze, T::Array[String])

    RO_SANCTIONED_DOMAINS = T.let(%w(
      sistema.com.ro
    ).freeze, T::Array[String])

    BE_SANCTIONED_DOMAINS = T.let(%w(
      ett.be
    ).freeze, T::Array[String])

    PS_SANCTIONED_DOMAINS = T.let(%w(
      herzallah.ps
    ).freeze, T::Array[String])

    OTHER_SANCTIONED_DOMAINS = T.let(%w(
      aithea.com
      ali2k.com
      aliabkar.com
      alfabank.com
      arvancloud.com
      arttronix.com
      arxfe.com
      baikalelectronics.com
      burevestnik.com
      cady-ic.com
      digikala.com
      eledtrodetal.com
      farzambehboudi.com
      gruzinov.com
      gsk-sd.com
      hasani.com
      highlandgold.com
      loqusgroup.com
      multiclet.com
      nexign.com
      peppersec.com
      polyus.com
      presstv.com
      promoil.com
      ptsecurity.com
      pumaenergy.com
      researchgroupnederland.com
      rusavtomatika.com
      status-it.com
      swisstecag.com
      ugmk.com
      umatex.com
      uralmash-ngo.com
      velesstroy.com
      vtb.com
      yadro.com
      zadna-int.com
      zrenergy.com
      bigmir.net
      dimkt.net
      radiocomp.net
      ubank.net
      rhc.aero
      chista.io
      morphbits.io
      mousavi.info
      develoop.run
      tornado.cash
      archlinux.us
      kompaniets.dev
      deeppavlov.ai
      sciprog.center
      tensy.org
      qubit.org
      digitalenergy.online
      uniguajira.edu.co
      vygon.consulting
      sharif.edu
    ).freeze, T::Array[String])

    IR_SANCTIONED_DOMAINS = T.let(%w(
      aliabkar.ir
      amnafzar.ir
      aut.ac.ir
      agri-jahad.ir
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
      parlamentocubano.gob.cu
      minint.gob.cu
      cubadefensa.cu
      tsp.gob.cu
      minrex.gob.cu
      infomed.sld.cu
      avianet.cu
      hidro.cu
      agrinfor.cu
      micons.cu
      min.cult.cu
      ceniai.inf.cu
      mfp.gov.cu
      fishnavy.inf.cu
      reduniv.edu.cu
      mic.cu
      sime.co.cu
      minjus.cu
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
        .concat(BE_SANCTIONED_DOMAINS)
        .concat(BY_SANCTIONED_DOMAINS)
        .concat(CN_SANCTIONED_DOMAINS)
        .concat(CU_SANCTIONED_DOMAINS)
        .concat(DE_SANCTIONED_DOMAINS)
        .concat(EU_SANCTIONED_DOMAINS)
        .concat(IN_SANCTIONED_DOMAINS)
        .concat(IR_SANCTIONED_DOMAINS)
        .concat(ME_SANCTIONED_DOMAINS)
        .concat(MV_SANCTIONED_DOMAINS)
        .concat(MX_SANCTIONED_DOMAINS)
        .concat(OTHER_SANCTIONED_DOMAINS)
        .concat(PK_SANCTIONED_DOMAINS)
        .concat(PS_SANCTIONED_DOMAINS)
        .concat(RO_SANCTIONED_DOMAINS)
        .concat(RS_SANCTIONED_DOMAINS)
        .concat(RU_SANCTIONED_DOMAINS)
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
