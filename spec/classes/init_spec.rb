# frozen_string_literal: true

require 'spec_helper'

describe 'ds389' do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      let(:facts) { os_facts }

      context "with #{os}" do
        it { is_expected.to compile.with_all_deps }
        it { is_expected.to create_class('ds389::install') }
        it { is_expected.to create_file('/usr/share/puppet_ds389_config') }
        it { is_expected.to create_file('/usr/share/puppet_ds389_config/ldifs') }
      end
      context 'with params' do
        let(:params) do
          {
            config_dir: '/my/dir',
         ldif_working_dir: '/my/other/dir',
         service_group: 'joe',
         instances: { 'inst1' => { 'root_dn' => 'pdq', 'base_dn' => 'xyz' } }
          }
        end

        it { is_expected.to compile.with_all_deps }
        it { is_expected.to create_class('ds389::install') }
        it { is_expected.to create_file('/my/dir').with({ 'group' => 'joe' }) }
        it { is_expected.to create_file('/my/other/dir').with({ 'group' => 'joe' }) }
        it { is_expected.to create_ds389__instance('inst1').with({ 'root_dn' => 'pdq', 'base_dn' => 'xyz' }) }
      end
    end
  end
end
