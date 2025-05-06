# frozen_string_literal: true

require 'spec_helper'

describe 'ds389::instance::dn::add', type: :define do
  context 'when on supported operating systems' do
    on_supported_os.each do |os, os_facts|
      context "with #{os}" do
        let(:facts) do
          os_facts
        end

        let(:title) do
          'test'
        end

        let(:params) do
          {
            dn: 'dc=foo,dc=bar',
            objectclass: ['MyObj2', 'MyObj1'],
            attrs: { 'foo' => 'bar', 'baz' => 'stuff' },
            root_dn: 'dn=thing',
            root_pw_file: '/some/seekrit/file.skrt',
            instance_name: 'my_service'
          }
        end

        let(:pre_condition) do
          <<~PRECOND
          include ds389
          PRECOND
        end

        let(:target_file) do
          "/usr/share/puppet_ds389_config/ldifs/#{params[:instance_name]}_add_dc=foo,dc=bar.ldif"
        end

        it { is_expected.to compile.with_all_deps }

        it do
          is_expected.to create_file(target_file)
            .with_owner('root')
            .with_group('root')
            .with_mode('0400')
            .with_content(
              sensitive(
                <<~CONTENT,
                dn: #{params[:dn]}
                dc: foo
                objectClass: MyObj1
                objectClass: MyObj2
                foo: bar
                baz: stuff
                CONTENT
              ),
            )
            .that_notifies("Exec[#{target_file}]")

          is_expected.to create_exec(target_file)
            .with_command(
              %(ldapadd -x -D '#{params[:root_dn]}' -y '#{params[:root_pw_file]}' -H ldap://127.0.0.1:389 -f '#{target_file}'),
            )
            .with_unless(
              %(ldapsearch -x -D '#{params[:root_dn]}' -y '#{params[:root_pw_file]}' -H ldap://127.0.0.1:389 -LLL -s base -S '' -o ldif-wrap=no -b '#{params[:dn]}'),
            )
            .with_path(['/bin', '/usr/bin'])
        end

        it { is_expected.not_to create_service(params[:instance_name]) }

        context 'when restarting the service' do
          let(:params) do
            {
              dn: 'dc=foo,dc=bar',
              objectclass: ['MyObj2', 'MyObj1'],
              attrs: { 'foo' => 'bar', 'baz' => 'stuff' },
              root_dn: 'dn=thing',
              root_pw_file: '/some/seekrit/file.skrt',
              instance_name: 'my_service',
              restart_instance: true
            }
          end

          it { is_expected.to compile.with_all_deps }

          it { is_expected.to create_ds389__instance__service(params[:instance_name]) }

          it {
            is_expected.to create_exec("Restart #{params[:instance_name]}")
              .with_command("/sbin/restart-dirsrv #{params[:instance_name]}")
              .with_refreshonly(true)
              .that_requires("Exec[#{target_file}]")
          }
        end
      end
    end
  end
end
