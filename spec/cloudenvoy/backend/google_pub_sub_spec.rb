# frozen_string_literal: true

require 'cloudenvoy/backend/google_pub_sub'

RSpec.describe Cloudenvoy::Backend::GooglePubSub do
  let(:gcp_project_id) { Cloudenvoy.config.gcp_project_id }
  let(:emulator_host) { Cloudenvoy.config.emulator_host }
  let(:backend) { instance_double(Google::Cloud::PubSub::Project) }
  let(:gcp_topic) { instance_double(Google::Cloud::PubSub::Topic) }

  describe '.config' do
    subject { described_class.config }

    it { is_expected.to eq(Cloudenvoy.config) }
  end

  describe '.development?' do
    subject { described_class }

    context 'with development mode' do
      before { allow(described_class.config).to receive(:mode).and_return(:development) }

      it { is_expected.to be_development }
    end

    context 'with other mode' do
      before { allow(described_class.config).to receive(:mode).and_return(:production) }

      it { is_expected.not_to be_development }
    end
  end

  describe '.backend' do
    subject { described_class.backend }

    before do
      described_class.instance_variable_set('@backend', nil)
      allow(Google::Cloud::PubSub).to receive(:new).with(expected_attrs).and_return(backend)
    end

    context 'with development mode' do
      let(:expected_attrs) { { project_id: gcp_project_id, emulator_host: emulator_host } }

      before { allow(described_class).to receive(:development?).and_return(true) }
      it { is_expected.to eq(backend) }
    end

    context 'with any other mode' do
      let(:expected_attrs) { { project_id: gcp_project_id } }

      before { allow(described_class).to receive(:development?).and_return(false) }
      it { is_expected.to eq(backend) }
    end
  end

  describe '.webhook_url' do
    subject { described_class.webhook_url }

    let(:token) { '123' }

    before { allow(Cloudenvoy::Authenticator).to receive(:verification_token).and_return(token) }
    it { is_expected.to eq("#{described_class.config.processor_url}?token=#{token}") }
  end

  describe '.publish' do
    subject { described_class.publish(topic, payload, metadata) }

    let(:topic) { 'some-topic' }
    let(:payload) { { foo: 'bar' } }
    let(:metadata) { { some: 'attribute' } }
    let(:gcp_msg) { instance_double(Google::Cloud::PubSub::Message, message_id: '123') }
    let(:expected_msg) do
      {
        class: Cloudenvoy::Message,
        id: gcp_msg.message_id,
        topic: topic,
        payload: payload,
        metadata: metadata
      }
    end

    before do
      expect(described_class).to receive(:backend).and_return(backend)
      expect(backend).to receive(:topic).with(topic, skip_lookup: true).and_return(gcp_topic)
      expect(gcp_topic).to receive(:publish).with(payload.to_json, metadata).and_return(gcp_msg)
    end

    it { is_expected.to have_attributes(expected_msg) }
  end

  describe '.publish_all' do
    subject { described_class.publish_all(topic, [[payload1, metadata1], [payload2, metadata2]]) }

    let(:topic) { 'some-topic' }

    let(:payload1) { { foo: 'bar1' } }
    let(:metadata1) { { some: 'attribute1' } }
    let(:payload2) { { foo: 'bar2' } }
    let(:metadata2) { { some: 'attribute2' } }

    let(:gcp_batch) { instance_double(Google::Cloud::PubSub::BatchPublisher) }
    let(:gcp_msg1) { instance_double(Google::Cloud::PubSub::Message, message_id: '123') }
    let(:gcp_msg2) { instance_double(Google::Cloud::PubSub::Message, message_id: '321') }
    let(:expected_ret) do
      [
        {
          class: Cloudenvoy::Message,
          id: gcp_msg1.message_id,
          topic: topic,
          payload: payload1,
          metadata: metadata1
        },
        {
          class: Cloudenvoy::Message,
          id: gcp_msg2.message_id,
          topic: topic,
          payload: payload2,
          metadata: metadata2
        }
      ]
    end

    before do
      expect(described_class).to receive(:backend).and_return(backend)
      expect(backend).to receive(:topic).with(topic, skip_lookup: true).and_return(gcp_topic)
      expect(gcp_topic).to receive(:publish).and_yield(gcp_batch).and_return([gcp_msg1, gcp_msg2])
      expect(gcp_batch).to receive(:publish).with(payload1.to_json, metadata1).and_return(gcp_msg1)
      expect(gcp_batch).to receive(:publish).with(payload2.to_json, metadata2).and_return(gcp_msg2)
    end

    it { is_expected.to match(expected_ret.map { |e| have_attributes(e) }) }
  end

  describe '.upsert_subscription' do
    subject { described_class.upsert_subscription(topic, sub_name, opts) }

    let(:topic) { 'some-topic' }
    let(:sub_name) { 'some.name' }
    let(:opts) { { retain_acked: true } }
    let(:webhook_url) { "#{described_class.config.processor_url}?token=123" }
    let(:gcp_sub) { instance_double(Google::Cloud::PubSub::Subscription, name: 'some.sub') }
    let(:sub_opts) { opts.merge(endpoint: webhook_url) }
    let(:expected_sub) do
      {
        class: Cloudenvoy::Subscription,
        name: gcp_sub.name,
        original: gcp_sub
      }
    end

    before do
      allow(backend).to receive(:topic).with(topic, skip_lookup: true).and_return(gcp_topic)
      allow(gcp_topic).to receive(:subscribe).and_return(gcp_sub)
      allow(described_class).to receive_messages(backend: backend, webhook_url: webhook_url, development?: false)
    end

    context 'with development mode' do
      before do
        allow(described_class).to receive(:development?).and_return(true)
        expect(described_class).to receive(:upsert_topic).with(topic)
      end

      it { is_expected.to be_truthy }
    end

    context 'with other mode' do
      before do
        expect(described_class).not_to receive(:upsert_topic)
      end

      it { is_expected.to be_truthy }
    end

    context 'with non-existing subscription' do
      before do
        expect(gcp_topic).to receive(:subscribe)
          .with(sub_name, opts.merge(endpoint: webhook_url))
          .and_return(gcp_sub)
      end

      it { is_expected.to have_attributes(expected_sub) }
    end

    context 'with existing subscription' do
      before do
        expect(gcp_topic).to receive(:subscribe)
          .with(sub_name, sub_opts)
          .and_raise(Google::Cloud::AlreadyExistsError)
        expect(backend).to receive(:subscription).with(sub_name).and_return(gcp_sub)

        sub_opts.each { |k, v| expect(gcp_sub).to receive("#{k}=").with(v) }
      end

      it { is_expected.to have_attributes(expected_sub) }
    end
  end

  describe '.upsert_topic' do
    subject { described_class.upsert_topic(topic) }

    let(:topic) { 'some-topic' }
    let(:gcp_topic) { instance_double(Google::Cloud::PubSub::Topic, name: topic) }
    let(:expected_topic) do
      {
        class: Cloudenvoy::Topic,
        name: gcp_topic.name,
        original: gcp_topic
      }
    end

    before { allow(described_class).to receive(:backend).and_return(backend) }

    context 'with non-existing topic' do
      before { expect(backend).to receive(:create_topic).with(topic).and_return(gcp_topic) }
      it { is_expected.to have_attributes(expected_topic) }
    end

    context 'with existing topic' do
      before do
        expect(backend).to receive(:create_topic).with(topic).and_raise(Google::Cloud::AlreadyExistsError)
        expect(backend).to receive(:topic).with(topic).and_return(gcp_topic)
      end

      it { is_expected.to have_attributes(expected_topic) }
    end
  end
end
