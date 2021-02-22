require "secrets-env"
require "placeos-log-backend"

module App
  NAME    = "triggers"
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}

  Log         = ::Log.for(NAME)
  ENVIRONMENT = ENV["SG_ENV"]? || "development"

  DEFAULT_PORT          = (ENV["SG_SERVER_PORT"]? || 3000).to_i
  DEFAULT_HOST          = ENV["SG_SERVER_HOST"]? || "127.0.0.1"
  DEFAULT_PROCESS_COUNT = (ENV["SG_PROCESS_COUNT"]? || 1).to_i

  SMTP_SERVER = ENV["SMTP_SERVER"]? || "smtp.example.com"
  SMTP_PORT   = (ENV["SMTP_PORT"]? || 25).to_i
  SMTP_USER   = ENV["SMTP_USER"]? || ""
  SMTP_PASS   = ENV["SMTP_PASS"]? || ""
  SMTP_SECURE = ENV["SMTP_SECURE"]? || ""

  # HoundDog Configuration.
  # ----------------------------------
  # ETCD_HOST (default: "127.0.0.1")
  # ETCD_PORT (default: 2379)
  # ETCD_TTL  (default: 15)

  CORE_NAMESPACE = "core"

  class_getter discovery : HoundDog::Discovery { HoundDog::Discovery.new(CORE_NAMESPACE) }

  def self.smtp_authenticated?
    !SMTP_USER.empty?
  end

  def self.running_in_production?
    ENVIRONMENT == "production"
  end
end
