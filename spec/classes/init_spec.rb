# frozen_string_literal: true

require 'spec_helper'

describe 'ds389' do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      let(:facts) { os_facts }

      context "with #{os}" do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to create_class('ds389::install') }
        it { is_expected.not_to create_ds389__instance('puppet_default_root') }

        context 'when creating the default instance' do
          let(:params) do
            {
              'initialize_ds_root' => true
            }
          end

          it { is_expected.to compile.with_all_deps }
          it { is_expected.to create_ds389__instance('puppet_default_root') }
        end
      end
    end
  end
end
