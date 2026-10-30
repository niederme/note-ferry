import Foundation

extension CoreTests {
    static func interviewTests(root: URL) throws {
        let suite = "note-ferry-interview-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = ProviderSettings(defaults: defaults, bundleIdentifier: suite)
        check(settings.clarificationInterviewEnabled, "Interview should default on")
        settings.clarificationInterviewEnabled = false
        check(!ProviderSettings(defaults: defaults, bundleIdentifier: suite).clarificationInterviewEnabled, "Interview opt-out did not persist")
        settings.clarificationInterviewEnabled = true
        check(settings.clarificationInterviewEnabled, "Interview cannot be re-enabled")

        let source = "Jamie: I can send it Friday. Alex: We still need to review the proposal before deciding what to share with the project team."
        let question = ClarificationQuestion(question: "What will Jamie send?", excerpt: "Jamie: I can send it Friday.", options: ["The proposal", "The schedule"])
        let batch = InterviewBatch(questions: [question])
        var session = InterviewSession()
        try session.receive(batch, source: source)
        let id = session.pending[0].id
        rejects({ try session.answer([], provider: .codex) }, "Mismatched answers accepted")
        rejects({ try session.answer([String(repeating: "a", count: 2001)], provider: .codex) }, "Unbounded answer accepted")
        check(session.pending[0].id == id && session.history.isEmpty, "Invalid answer discarded pending question")
        try session.answer(["  Jamie offered to send the proposal, but did not commit.  "], provider: .codex)
        check(session.history[0].id == id && session.history[0].answer.hasPrefix("Jamie"), "Answer lost stable question association")
        let repeated = try batch.validated(source: source, history: session.history)
        check(repeated.questions.isEmpty, "Repeated question was shown again")
        for index in 1...4 {
            let next = ClarificationQuestion(question: "Clarification \(index)?", excerpt: "", options: [])
            try session.receive(InterviewBatch(questions: [next]), source: source)
            try session.answer([""], provider: .codex)
        }
        check(session.history.count == 5 && session.round == 5, "Interview incorrectly capped at three total questions")
        check(InterviewSession.summaryText(session.history).contains("offered") && !InterviewSession.summaryText(session.history).contains("Clarification 1"), "Unanswered questions became summary facts")
        let invented = InterviewBatch(questions: [ClarificationQuestion(question: "Who?", excerpt: "This never appeared.", options: [])])
        rejects({ _ = try invented.validated(source: source, history: []) }, "Fabricated excerpt accepted")
        rejects({ _ = try InterviewBatch(questions: Array(repeating: question, count: 4)).validated(source: source, history: []) }, "More than three questions in one batch accepted")
        let longAnswer = Clarification(id: "a", question: question, answer: String(repeating: "x", count: 1800))
        rejects({ try InterviewSession.validateAnswers([longAnswer], provider: .apple) }, "On-device context limit not enforced")
        try InterviewSession.validateAnswers([longAnswer], provider: .codex)

        let resources = root.appendingPathComponent("Resources")
        let summary = try ModelRequest.summary(transcript: source, context: "Jamie leads NOVA.", clarifications: session.history, resources: resources)
        let jsonStart = summary.payload.firstIndex(of: "{")!
        let body = try JSONSerialization.jsonObject(with: Data(summary.payload[jsonStart...].utf8)) as! [String: Any]
        check(body["transcript"] as? String == source, "Interview answers changed source text")
        check((body["clarifications"] as? [[String: Any]])?.count == 1, "Summary did not separate answered clarifications")
        check((body["unansweredQuestions"] as? [String])?.count == 4, "Skipped ambiguities were not carried forward as unanswered")
        let answerFields = (body["clarifications"] as! [[String: Any]])[0]
        check(answerFields["question"] as? String == question.question && answerFields["options"] == nil, "Unchosen suggestions leaked into summary evidence")
        let interview = try ModelRequest.interview(transcript: source, context: "", history: session.history, resources: resources)
        let historyBody = try JSONSerialization.jsonObject(with: Data(interview.payload.utf8)) as! [String: Any]
        check((historyBody["previousQuestions"] as? [[String: Any]])?.count == 5, "Follow-up request lost unanswered question history")

        let mock = root.appendingPathComponent("Tests/mock-codex.sh")
        setenv("NF_TEST_MODE", "interview", 1)
        defer { unsetenv("NF_TEST_MODE") }
        var tokens: TokenUsage?
        let generated = try CodexRunner().interview(transcript: source, context: "", history: [], resources: resources, executable: mock, onUsage: { tokens = $0 })
        check(generated.questions.count == 1 && tokens == TokenUsage(input: 100, output: 20), "Codex interview schema or usage failed")
        setenv("NF_TEST_MODE", "interview_empty", 1)
        let empty = try CodexRunner().interview(transcript: source, context: "", history: [], resources: resources, executable: mock)
        check(empty.questions.isEmpty, "Clear source did not finish interview")
        setenv("NF_TEST_MODE", "malformed", 1)
        rejects({ _ = try CodexRunner().interview(transcript: source, context: "", history: [], resources: resources, executable: mock) }, "Malformed interview response accepted")
        setenv("NF_TEST_MODE", "hang", 1)
        let cancelled = CodexRunner(timeout: 2)
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancelled.cancel() }
        do { _ = try cancelled.interview(transcript: source, context: "", history: [], resources: resources, executable: mock); fatalError("Interview cancellation ignored") }
        catch is CancellationError { checks += 1 }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockClaudeURLProtocol.self]
        let network = URLSession(configuration: configuration)
        defer { network.invalidateAndCancel(); MockClaudeURLProtocol.responseProvider = nil }
        let encoded = String(decoding: try JSONEncoder().encode(batch), as: UTF8.self)
        MockClaudeURLProtocol.status = 200
        MockClaudeURLProtocol.payload = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": encoded]], "stop_reason": "end_turn", "usage": ["input_tokens": 50, "output_tokens": 10]])
        let claude = try ClaudeRunner(session: network).interview(transcript: source, context: "", history: session.history, resources: resources, apiKey: "synthetic-test-key")
        check(claude.questions.isEmpty, "Claude repeated an answered question")
        let observed = try JSONSerialization.jsonObject(with: MockClaudeURLProtocol.observedBody) as! [String: Any]
        let format = (observed["output_config"] as! [String: Any])["format"] as! [String: Any]
        let schema = format["schema"] as! [String: Any]
        check((schema["properties"] as! [String: Any])["questions"] != nil, "Claude sent summary schema for interview")
        let messages = observed["messages"] as! [[String: String]]
        check(messages[0]["content"]?.contains("previousQuestions") == true, "Claude omitted interview history")

        var usage = InterviewUsage()
        usage.record(TokenUsage(input: 100, output: 20))
        usage.record(TokenUsage(input: 200, output: 30))
        check(usage.including(TokenUsage(input: 300, output: 40)) == TokenUsage(input: 600, output: 90), "Interview token total excluded a round or summary")
        usage.record(nil)
        check(usage.including(TokenUsage(input: 300, output: 40)) == nil, "Incomplete token total presented as complete")
    }
}
