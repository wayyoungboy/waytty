enum AiProvider { anthropic, openai, gemini }

class AiProviderConfig {
  final String apiKey;
  final String model;
  final String? endpoint;

  const AiProviderConfig({required this.apiKey, required this.model, this.endpoint});
}
