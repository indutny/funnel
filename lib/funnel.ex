defmodule Funnel do
  @type full_cipher() :: {atom(), atom(), atom(), atom()}
  @type cipher() :: {atom(), atom(), atom()}

  @spec get_ciphers() :: [full_cipher() | cipher()]
  def get_ciphers() do
    [
      {:ecdhe_ecdsa, :chacha20_poly1305, :aead, :sha256},
      {:ecdhe_rsa, :chacha20_poly1305, :aead, :sha256},
      {:ecdhe_ecdsa, :aes_256_gcm, :aead, :sha384},
      {:ecdhe_rsa, :aes_256_gcm, :aead, :sha384},
      {:ecdhe_ecdsa, :aes_256_cbc, :sha384, :sha384},
      {:ecdhe_rsa, :aes_256_cbc, :sha384, :sha384},
      {:ecdhe_ecdsa, :aes_128_gcm, :aead, :sha256},
      {:ecdhe_rsa, :aes_128_gcm, :aead, :sha256},
      {:ecdhe_ecdsa, :aes_128_cbc, :sha256, :sha256},
      {:ecdhe_rsa, :aes_128_cbc, :sha256, :sha256},
      {:dhe_rsa, :chacha20_poly1305, :aead, :sha256},
      {:dhe_rsa, :aes_256_gcm, :aead, :sha384},
      {:dhe_rsa, :aes_256_cbc, :sha256},
      {:dhe_rsa, :aes_128_gcm, :aead, :sha256},
      {:dhe_rsa, :aes_128_cbc, :sha256},
      {:any, :chacha20_poly1305, :aead, :sha256},
      {:any, :aes_256_gcm, :aead, :sha384},
      {:any, :aes_128_gcm, :aead, :sha256}
    ]
  end
end
