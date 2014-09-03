require 'rest_client'

class JCClient < Struct.new( :host )

    def request http_method, uri, params = {}
        begin
            resp = RestClient.send(http_method, "#{host}/uri", params)
        rescue => e
            raise "unsuccessfull return from <#{http_method}> to <#{host}/#{uri}> with params:#{params} :  <#{e.response.code}>\n\n<#{e.response}>"
        end
        resp
    end
end


