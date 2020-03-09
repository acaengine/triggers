module PlaceOS::Triggers
  APP_NAME    = "triggers"
  API_VERSION = "v1"
  VERSION     = {{ `shards version "#{__DIR__}"`.chomp.stringify.downcase }}
end
