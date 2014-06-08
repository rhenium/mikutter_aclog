require "simple_oauth"
require "open-uri"
require "json"

Plugin.create(:mikutter_aclog) do
  ACLOG_BASE = "http://aclog.koba789.com"

  def aclog_request(path)
    provider = "https://api.twitter.com/1.1/account/verify_credentials.json"
    oauth = { consumer_key: Service.primary.consumer_key,
              consumer_secret: Service.primary.consumer_secret,
              token: Service.primary.a_token,
              token_secret: Service.primary.a_secret }
    h = SimpleOAuth::Header.new(:get, provider, {}, oauth)

    thread = Thread.new do
      fd = open(ACLOG_BASE + path, "X-Auth-Service-Provider" => provider, "X-Verify-Credentials-Authorization" => h.to_s)
      fd.read end
    thread.abort_on_exception = false
    thread.next { |str| JSON.parse(str).symbolize } end

  def aclog_tweet(id)
    aclog_request("/api/tweets/show.json?id=#{id}") end

  def aclog_user_best(user)
    aclog_request("/api/tweets/user_best.json?user_id=#{user[:id]}&count=100").next {|arr|
      ids = arr.map { |tweet| tweet[:id] }
      (Service.primary/:statuses/:lookup).messages(id: ids.join(",")) } end

  command(:mikutter_aclog_get_voters,
          name: "ふぁぼったユーザーを aclog から取得",
          condition: Plugin::Command[:CanReplyAll],
          visible: true,
          role: :timeline) do |m|
    m.messages.each do |msg|
      Thread.new {
        begin
          hash = aclog_tweet(msg[:id])

          ((hash[:favoriters] || []).take(200) + (hash[:retweeters] || []).take(200)).uniq.each_slice(100) do |ids|
            Service.primary.user_lookup(user_id: ids.join(",")).next {|res|
              looked_up_users = {}
              res.each { |re|
                looked_up_users[re.id] = re }
              
              Gdk::MiraclePainter.findbymessage_d(msg).next { |mps|
                mps.deach { |mp|
                  favorite_subpart = mp.subparts.find { |sp| sp.class == Gdk::SubPartsFavorite } 
                  hash[:favoriters].each do |user_id|
                    user = looked_up_users[user_id]
                    if user
                      favorite_subpart.add(user) end end

                  retweet_subpart = mp.subparts.find { |sp| sp.class == Gdk::SubPartsRetweet }
                  hash[:retweeters].each do |user_id|
                    user = looked_up_users[user_id]
                    if user
                      retweet_subpart.add(user) end end
                  mp.on_modify
                } } } end
        rescue StandardError, Timeout::TimeoutError
          warn $!
          warn $@
        end } end end

  profiletab(:aclog_best, "aclog best") do
    set_icon File.join(File.dirname(__FILE__), "aclog.png")
    i_timeline = timeline nil do
      order do |message|
        message[:retweet_count].to_i + message[:favorite_count].to_i end end
    aclog_user_best(user).next { |tl|
      p tl.first
      #i_timeline << tl.take(6)
    }.terminate("@%{user} の aclog ベストツイートが取得ふぇきませんでした(◞‸◟)" % { user: user[:idname] })
  end
end
