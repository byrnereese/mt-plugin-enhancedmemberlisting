package EnhancedMemberListing::Plugin;

use strict;
use MT::Util qw( format_ts );
use Digest::MD5 qw( md5_hex );

sub list {
    my $app = shift;

    my $blog_id = $app->param('blog_id');
    $app->return_to_dashboard( redirect => 1 )
      unless $blog_id;

    my $blog = $app->blog;
    my $user = $app->user;

    my $super_user = 1 if $user->is_superuser();
    my $args       = {};
    my $terms      = {};
    my $param = { list_noncron => 1 };
    $args->{join} =
      MT::Permission->join_on( 'author_id', { blog_id => $blog_id, } );

    $args->{sort_order} = 'created_on';
    $args->{direction}  = 'descend';

    $param->{saved} = 1 if $app->param('saved');
    $param->{search_label} = $app->translate('Users');
    $param->{object_type} = 'user';

    require MT::Association;
    require MT::Role;
    my @all_roles = MT::Role->load( undef, { sort => 'name' });

    my $sel_role = 0;
    my $filter = $app->param('filter') || '';
    if ($filter eq 'role') {
        my $val = scalar $app->param('filter_val');
        if ($val) {
            $sel_role = $val;
            $args->{join} = MT::Association->join_on('author_id', { blog_id => $blog_id, role_id => $val });
        }
    }
    elsif ($filter eq 'status') {
        my $val = $app->param('filter_val');
        if ($val eq 'disabled') {
            $terms->{status} = 2;
        }
        elsif ($val eq 'pending') {
            $terms->{status} = 3;
        }
        else {
            $terms->{status} = 1;
        }
    }

    my @role_loop;
    foreach my $r (@all_roles) {
        push @role_loop, { role_id => $r->id, role_name => $r->name, selected => $r->id == $sel_role };
    }
    $param->{role_loop} = \@role_loop;
    my $hasher = sub {
        my ( $obj, $row ) = @_;
        if ( ( $row->{email} || '' ) !~ m/@/ ) {
            $row->{email} = '';
        }
	$row->{userpic} = $obj->userpic_url( { Width => 50 } );
	$row->{user_id} = $obj->id;
	$row->{user_name} = $obj->nickname;
	$row->{user_email} = $obj->email;
	$row->{user_email_md5} = md5_hex($obj->email);
	$row->{user_website} = $obj->url;
	$row->{user_username} = lc($obj->nickname) ne lc($obj->name) ? $obj->name : undef;

	$row->{status_pending} = $obj->status == MT::Author::PENDING();
	$row->{status_banned} = $obj->is_banned($blog_id);
	$row->{status_trusted} = $obj->is_trusted($blog_id);
	$row->{status_disabled} = !$obj->is_active();

	$row->{user_entry_count} = MT::Entry->count({ author_id => $obj->id, blog_id => $blog_id });
	$row->{user_comment_count} = MT::Comment->count({ commenter_id => $obj->id, blog_id => $blog_id });

        $row->{created_on} = format_ts( '%B %e, %Y', $obj->created_on, $blog );
        if ( $row->{created_by} ) {
            if ( my $created_by = MT::Author->load( $row->{created_by} ) ) {
                $row->{created_by} = $created_by->name;
            }
            else {
                $row->{created_by} = $app->translate('*User deleted*');
            }
        }
        $row->{is_me}           = $row->{id} == $user->id;
        $row->{has_edit_access} = 1 if $super_user;
        $row->{usertype_author} = 1 if $obj->type == MT::Author::AUTHOR();
        if ( $obj->type == MT::Author::COMMENTER() ) {
            $row->{usertype_commenter} = 1;
            $row->{status_trusted} = 1 if $obj->is_trusted($blog_id);
            if ($row->{user_name} =~ m/^[a-f0-9]{32}$/) {
                $row->{user_name} = $row->{nickname} || $row->{url};
            }
        }
        $row->{status_enabled} = 1 if $obj->status == 1;
        my @roles = MT::Role->load(undef, { join => MT::Association->join_on('role_id', { author_id => $row->{id}, blog_id => $blog_id }, { unique => 1 })});
        my @role_loop;
        foreach my $role (@roles) {
            my @perms;
            my @all_perms = @{ MT::Permission->perms() };
            foreach (@all_perms) {
                next unless length( $_->[1] || '' );
                push @perms, $_->[1]
                  if $role->has( $_->[0] );
            }
	    MT->log({message => "roles: " . $#roles . ", name: " . $role->name . "\n"});
            my $role_perms = join(", ", @perms);
            push @role_loop, { 
		role_name => $role->name, role_id => $role->id, role_perms => $role_perms, 
	    } unless ($#roles > 0 && $role->name eq 'Commenter');
        }
        $row->{role_loop} = \@role_loop;
	if (@roles) {
	    $row->{user_role} = $#role_loop == 0 ? $role_loop[0]->{role_name} : 'Various';
	} else {
	    $row->{user_role} = 'Commenter';
	}
	$row->{user_role_lc} = lc $row->{user_role};
        $row->{auth_icon_url} = $obj->auth_icon_url;
    };
    $param->{screen_id} = "list-member";

    return $app->listing(
        {
            type     => 'user',
            template => 'list.tmpl',
            terms    => $terms,
            params   => $param,
            args     => $args,
            code     => $hasher,
        }
    );

}

1;
