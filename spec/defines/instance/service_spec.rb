# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance::service', type: :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:pre_condition) do
          <<~PRECOND
          function assert_private(){}

          include ds389
          PRECOND
        end

        let(:facts) do
          os_facts
        end

        let(:title) do
          'test'
        end

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to create_service("dirsrv@#{title}")
            .with_ensure('running')
            .with_enable(true)
            .with_hasrestart(true)
        end
      end
    end
  end
end
