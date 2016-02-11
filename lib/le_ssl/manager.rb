module LeSsl
	class Manager
		PRODUCTION_ENDPOINT = 'https://acme-v01.api.letsencrypt.org/'
		DEVELOPMENT_ENDPOINT = 'https://acme-staging.api.letsencrypt.org/'

		def initialize(options={})
			email = options[:email] || ENV['CERT_ACCOUNT_EMAIL'].presence

			raise LeSsl::NoContactEmailError if email.nil?
			raise LeSsl::TermsNotAcceptedError unless options[:agree_terms] == true

			self.private_key = options[:private_key].presence

			private_key			# Check private key

			register(email) unless options[:skip_register] == true
		end

		def authorize_for_domain(domain)
			authorization = client.authorize(domain: domain)
			challenge = authorization.http01

			file_name = Rails.root.join('public', challenge.filename)
			dir = File.dirname(Rails.root.join('public', challenge.filename))

			FileUtils.mkdir_p(dir)

			File.write(file_name, challenge.file_content)

			challenge.request_verification

			sleep(1)
			
			File.delete(file_name) if challenge.verify_status == 'invalid'
			
			return challenge.verify_status
		end

		def request_certificate(*domains)
			csr = Acme::Client::CertificateRequest.new(names: domains)
			certificate = client.new_certificate(csr)

			FileUtils.mkdir_p(Rails.root.join('config', 'ssl'))

			File.write(Rails.root.join('config', 'ssl', 'privkey.pem'), certificate.request.private_key.to_pem)
			File.write(Rails.root.join('config', 'ssl', 'cert.pem'), certificate.to_pem)
			File.write(Rails.root.join('config', 'ssl', 'chain.pem'), certificate.chain_to_pem)
			File.write(Rails.root.join('config', 'ssl', 'fullchain.pem'), certificate.fullchain_to_pem)

			return certificate
		rescue Acme::Client::Error::Unauthorized => e
			raise LeSsl::UnauthorizedError, e.message
		end

		def register(email)
			client.register(contact: "mailto:#{email}").agree_terms
			return true
		rescue Acme::Client::Error::Malformed => e
			return false if e.message == "Registration key is already in use"
			raise e
		end

		private

		def private_key=(key)
			if key.is_a?(OpenSSL::PKey::RSA)
				@private_key = key
			elsif key.is_a?(String)
				@private_key = OpenSSL::PKey::RSA.new(key)
			elsif key.nil?
				nil		# Return silently
			else
				raise LeSsl::PrivateKeyInvalidFormat
			end
		end

		def private_key
			self.private_key = ENV['CERT_ACCOUNT_PRIVATE_KEY'].presence if @private_key.nil?
			raise(LeSsl::NoPrivateKeyError, "No private key for certificate account found") if @private_key.nil?
			
			@private_key
		end

		def client
			@acme_client ||= Acme::Client.new(private_key: private_key, endpoint: (Rails.env.development? ? DEVELOPMENT_ENDPOINT : PRODUCTION_ENDPOINT))
		end
	end
end