package bot

import (
	"encoding/json"
	"path/filepath"
	"testing"
	"time"
)

func TestPromotionRules(t *testing.T) {
	now := time.Unix(1000, 0)
	for _, tc := range []struct {
		name, text string
		buttons    bool
		count      int
		joined     time.Time
		age        time.Duration
		reason     string
	}{
		{name: "reported betting promotion", text: "PARIMATCH—The world's largest betting platform. Customer Service Bot: @gchat84c70874bot. Lightning-fast withdrawals. Register an account: parimatch.ltd. Receive $500!", reason: "betting-promotion"},
		{name: "generic betting pitch", text: "Join our sports betting platform and claim your welcome bonus https://example.com", reason: "betting-promotion"},
		{name: "inline buttons", text: "Click below", buttons: true, reason: "inline-buttons"},
		{name: "same second first post", text: "hello", joined: now, reason: "immediate-join-post"},
		{name: "subsecond first post", text: "hello", joined: now.Add(-500 * time.Millisecond), reason: "immediate-join-post"},
		{name: "one second boundary", text: "hello", joined: now.Add(-time.Second)},
		{name: "missing join", text: "hello"},
		{name: "future join", text: "hello", joined: now.Add(time.Second)},
		{name: "not first post", text: "hello", count: 1, joined: now},
		{name: "empty join service", joined: now},
		{name: "technical betting discussion", text: "How would you design a betting platform in Go?"},
		{name: "registration alone", text: "Register for the Go meetup https://example.com"},
		{name: "word buttons alone", text: "How do I add buttons to my Telegram bot?"},
		{name: "ten posts protected", text: "Register for sports betting bonus @some_spammer", buttons: true, count: 10, joined: now},
		{name: "old spam protected", text: "Join our betting platform and claim a bonus @some_spammer", age: 25 * time.Hour},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := EvaluateMessage(testConfig(), HistoryView{MessageCount: tc.count, JoinedAt: tc.joined}, MessageEvent{MessageID: 72783, Text: tc.text, HasInlineButtons: tc.buttons, At: now.Add(-tc.age), Now: now})
			if d.Reason != tc.reason || d.Moderate != (tc.reason != "") {
				t.Fatalf("want reason %q, got %#v", tc.reason, d)
			}
		})
	}
}

func TestInlineButtonBotMessageAndAdminGuard(t *testing.T) {
	for _, status := range []string{"member", "administrator", "creator"} {
		t.Run(status, func(t *testing.T) {
			store, err := OpenFileStore(filepath.Join(t.TempDir(), "state.json"))
			if err != nil {
				t.Fatal(err)
			}
			var u rawTelegramUpdate
			err = json.Unmarshal([]byte(`{"update_id":1,"message":{"message_id":72783,"date":1000,"chat":{"id":-100123,"type":"supergroup"},"from":{"id":55,"is_bot":true,"first_name":"Spam"},"text":"Click below","reply_markup":{"inline_keyboard":[[{"text":"Join","url":"https://example.com"}]]}}}`), &u)
			if err != nil {
				t.Fatal(err)
			}
			client := &fakeTelegramClient{memberStatus: status}
			if err := HandleRawUpdate(testConfig(), store, client, u, time.Unix(1000, 0)); err != nil {
				t.Fatal(err)
			}
			want := 0
			if status == "member" {
				want = 1
			}
			if len(client.deleted) != want || len(client.banned) != want {
				t.Fatalf("status %s: deleted=%v banned=%v", status, client.deleted, client.banned)
			}
		})
	}
}

func TestInlineResultBansPostingUser(t *testing.T) {
	store, err := OpenFileStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	var u rawTelegramUpdate
	if err := json.Unmarshal([]byte(`{"update_id":1,"message":{"message_id":72783,"date":1000,"chat":{"id":-100123,"type":"supergroup"},"from":{"id":55,"is_bot":false,"first_name":"Poster"},"via_bot":{"id":99,"is_bot":true,"first_name":"Inline bot"},"text":"Click below","reply_markup":{"inline_keyboard":[[{"text":"Join","url":"https://example.com"}]]}}}`), &u); err != nil {
		t.Fatal(err)
	}
	client := &fakeTelegramClient{}
	if err := HandleRawUpdate(testConfig(), store, client, u, time.Unix(1000, 0)); err != nil {
		t.Fatal(err)
	}
	if len(client.banned) != 1 || client.banned[0] != 55 {
		t.Fatalf("wrong attribution: %v", client.banned)
	}
}

func TestJoinServiceDoesNotConsumeFirstPost(t *testing.T) {
	store, err := OpenFileStore(filepath.Join(t.TempDir(), "state.json"))
	if err != nil {
		t.Fatal(err)
	}
	client := &fakeTelegramClient{}
	for _, raw := range []string{
		`{"message":{"message_id":1,"date":1000,"chat":{"id":-100123,"type":"supergroup"},"from":{"id":55,"first_name":"Poster"},"new_chat_members":[{"id":55,"first_name":"Poster"}]}}`,
		`{"message":{"message_id":2,"date":1000,"chat":{"id":-100123,"type":"supergroup"},"from":{"id":55,"first_name":"Poster"},"text":"hello"}}`,
	} {
		var u rawTelegramUpdate
		if err := json.Unmarshal([]byte(raw), &u); err != nil {
			t.Fatal(err)
		}
		if err := HandleRawUpdate(testConfig(), store, client, u, time.Unix(1000, 0)); err != nil {
			t.Fatal(err)
		}
	}
	if len(client.banned) != 1 || client.banned[0] != 55 {
		t.Fatalf("first post missed: %v", client.banned)
	}
}
