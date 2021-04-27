defmodule FunnelSMTPDKIMTest do
  use ExUnit.Case, async: true

  alias FunnelSMTP.DKIM
  alias FunnelSMTP.Mail

  doctest DKIM

  setup do
    dkim =
      start_supervised!(
        {DKIM,
         %DKIM.Config{
           private_key: "priv/keys/dkim-private.pem",
           domain: "funnel.example",
           selector: "static"
         }}
      )

    %{dkim: dkim}
  end

  test "should sign headers and body", %{dkim: dkim} do
    mail =
      Mail.new(
        "sender@example.com",
        %{},
        Enum.join(
          [
            "Header-1: value-1",
            "Header-2: value-2",
            "",
            "Body"
          ],
          "\r\n"
        )
      )

    assert {:ok, signed} = DKIM.sign(dkim, mail, ["header-1"])

    assert String.split(signed.data, "\r\n") == [
             "DKIM-Signature: v=1; a=rsa-sha256; c=simple/simple;",
             "                d=funnel.example; s=static;",
             "                h=header-1;",
             "                bh=x/N8/ivRfGMxF56p8/vkrTaHlPadGijHRWz0MB878Wk=",
             "                b=MwnBOkqbKEd6qkhXDcXoyKn88EF6B1SA26qKW32qssd+u/Qptwjy388NdZuqZtng",
             " C/8eX/A62rByx5XUbx6XRSTsNua5UnNz+p2rMdUZos9zbFyzEFxFboxJJP5EQX3b",
             " 0H5UwSJQr1JEuNJgJSZL9oBoMnySE781Obyeyq9j63/UV745BJXjVtHCPcHscos9",
             " GNeEl90TsY+7h206eXGIKsxlRHB0bKl+W7FaHcBnefGGM3WkiwA5PcL08sZF3rAs",
             " zuR1L/v+YSNdSTmS7KercNATpaBjNfCdl2NgzhGa6GUd+7fkcXzXj3r0FlBI4SP3",
             " bZjVL9qigiqZbfmJJp5owQ==Header-1: value-1",
             "Header-2: value-2",
             "",
             "Body"
           ]

    assert {:ok, signed} = DKIM.sign(dkim, mail, ["header-1", "header-2"])

    assert String.split(signed.data, "\r\n") == [
             "DKIM-Signature: v=1; a=rsa-sha256; c=simple/simple;",
             "                d=funnel.example; s=static;",
             "                h=header-1:header-2;",
             "                bh=x/N8/ivRfGMxF56p8/vkrTaHlPadGijHRWz0MB878Wk=",
             "                b=BOaiSlBnof0I9DoDwy0/KIl4NzuK21LNRhxo+Gdin5S/m20jvs9VQgEyePx9Ke/n",
             " k1KBArmJLrcbTx7uHiK5jd80PFX5tCwMAcogANu5pCfrgsaitAkfC0L9bV/ftfDA",
             " R+k1+u68yCReTvZ4o85QUM6+txfG/EwlMYyrhMpJPVpZwnDMRHYnV1F4q34UieLi",
             " 9FVm2j3Ncx4Q6ZMvWWGwR21xlmudZaHtvsFqOnzMup4wOavMzMiooLaTIbBEBMdL",
             " FIxkB0oBM38/Li32oaLRvrnY0ZboI+PiegHCZ8VyOZ/daWoKjiwymNGwcXtjYLZZ",
             " 37QkquJKLDXxtuLcyIQZBA==Header-1: value-1",
             "Header-2: value-2",
             "",
             "Body"
           ]
  end
end
