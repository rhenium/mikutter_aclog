require "open-uri"
require "json"

Plugin.create(:mikutter_aclog) do
  ACLOG_BASE = "http://aclog.koba789.com"

  def aclog_request(path)
    provider = "https://api.twitter.com/1.1/account/verify_credentials.json"

    token = Service.primary.access_token
    consumer = OAuth::Consumer.new(token.consumer.key, token.consumer.secret, site: "https://api.twitter.com")
    _req = consumer.create_signed_request(:get, URI.parse(provider).path, token)
    auth_header = _req["Authorization"]

    thread = Thread.new do
      res = open(ACLOG_BASE + path, "X-Auth-Service-Provider" => provider, "X-Verify-Credentials-Authorization" => auth_header)
      res.read end
    thread.abort_on_exception = false
    thread.next { |str| JSON.parse(str).symbolize } end

  def aclog_tweet(id)
    aclog_request("/api/tweets/show.json?id=#{id}") end

  def aclog_user_best(user)
    aclog_request("/api/tweets/user_best.json?user_id=#{user[:id]}&count=100").next {|arr|
      ids = arr.map { |tweet| tweet[:id] }
      (Service.primary/:statuses/:lookup).messages(id: ids.join(",")) } end

  def aclog_user_stats(user)
    aclog_request("/api/users/stats.json?id=#{user[:id]}") end

  def userdb
    @userdb ||= {} end

  class User
    def count_favorite_by
      Thread.new {
        m = open("http://favstar.fm/users/#{idname}").read.match(/<div[\s]+class='fs-value'[\s]*>[\s]*([0-9,]+)[\s]*<\/div>[\s]*<div[\s]+class='fs-title'[\s]*>[\s]*Favs[\s]*Received[\s]*<\/div>/) rescue nil
        m[1].gsub(",", "").to_i rescue "-"
      }.next { |favstar|
        Plugin.create(:mikutter_aclog).aclog_user_stats(self).next { |aclog_ret|
          aclog = aclog_ret[:reactions_count] rescue "-"
          aclog = "(#{aclog})" unless aclog_ret[:registered]
          @value[:favouritesby_count] = "#{favstar}/#{aclog}" } } end
  end

  command(:mikutter_aclog_get_voters,
          name: "ふぁぼったユーザーを aclog から取得",
          condition: Plugin::Command[:CanReplyAll],
          visible: true,
          role: :timeline) do |m|
    m.messages.each do |msg|
      aclog_tweet(msg[:id]).next { |hash|
        (((hash[:favoriters] || []).take(200) + (hash[:retweeters] || []).take(200)).uniq - userdb.keys).each_slice(100) do |ids|
          Service.primary.user_lookup(user_id: ids.join(",")).next {|res|
            res.each { |re|
              userdb[re.id] = re }
            Gdk::MiraclePainter.findbymessage_d(msg).next do |mps|
              mps.deach { |mp|
                mp.subparts.each do |sp|
                  if sp.class == Gdk::SubPartsFavorite
                    hash[:favoriters].each { |id|
                      if userdb.key?(id)
                        sp.votes.delete(userdb[id])
                        sp.votes << userdb[id] end }
                  elsif sp.class == Gdk::SubPartsRetweet
                    hash[:retweeters].each { |id|
                      if userdb.key?(id)
                        sp.votes.delete(userdb[id])
                        sp.votes << userdb[id] end } end end
                mp.reset_height } end } end
      }.terminate("failed to retrieve voters") end end

  profiletab(:aclog_best, "aclog best") do
    set_icon File.join(File.dirname(__FILE__), "aclog.png")
    i_timeline = timeline nil do
      order do |message|
        message[:retweet_count].to_i + message[:favorite_count].to_i end end
    aclog_user_best(user).next { |tl|
      i_timeline << tl
    }.terminate("@%{user} の aclog user_best が取得できませんでした(◞‸◟)" % { user: user[:idname] }) end
end
