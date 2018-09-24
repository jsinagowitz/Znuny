# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Output::HTML::DashboardUserOnline;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    # get needed parameters
    for my $Needed (qw(Config Name UserID)) {
        die "Got no $Needed!" if ( !$Self->{$Needed} );
    }

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get current filter
    my $Name = $ParamObject->GetParam( Param => 'Name' ) || '';
    my $PreferencesKey = 'UserDashboardUserOnlineFilter' . $Self->{Name};
    if ( $Self->{Name} eq $Name ) {
        $Self->{Filter} = $ParamObject->GetParam( Param => 'Filter' ) || '';
    }

    # remember filter
    if ( $Self->{Filter} ) {

        # update session
        $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => $PreferencesKey,
            Value     => $Self->{Filter},
        );

        # update preferences
        if ( !$Self->{ConfigObject}->Get('DemoSystem') ) {
            $Kernel::OM->Get('Kernel::System::User')->SetPreferences(
                UserID => $Self->{UserID},
                Key    => $PreferencesKey,
                Value  => $Self->{Filter},
            );
        }
    }

    if ( !$Self->{Filter} ) {
        $Self->{Filter} = $Self->{$PreferencesKey} || $Self->{Config}->{Filter} || 'Agent';
    }

    $Self->{PrefKey} = 'UserDashboardPref' . $Self->{Name} . '-Shown';

    $Self->{PageShown} = $Kernel::OM->Get('Kernel::Output::HTML::Layout')->{ $Self->{PrefKey} }
        || $Self->{Config}->{Limit};

    $Self->{StartHit} = int( $ParamObject->GetParam( Param => 'StartHit' ) || 1 );

    $Self->{CacheKey} = $Self->{Name} . '::' . $Self->{Filter};

    # get configuration for the full name order for user names
    # and append it to the cache key to make sure, that the
    # correct data will be displayed every time
    my $FirstnameLastNameOrder = $Self->{ConfigObject}->Get('FirstnameLastnameOrder') || 0;
    $Self->{CacheKey} .= '::' . $FirstnameLastNameOrder;

    return $Self;
}

sub Preferences {
    my ( $Self, %Param ) = @_;

    my @Params = (
        {
            Desc  => 'Shown',
            Name  => $Self->{PrefKey},
            Block => 'Option',
            Data  => {
                5  => ' 5',
                10 => '10',
                15 => '15',
                20 => '20',
                25 => '25',
            },
            SelectedID  => $Self->{PageShown},
            Translation => 0,
        },
    );

    return @Params;
}

sub Config {
    my ( $Self, %Param ) = @_;

    return (
        %{ $Self->{Config} },

        # remember, do not allow to use page cache
        # (it's not working because of internal filter)
        CacheKey => undef,
        CacheTTL => undef,
    );
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $SessionMaxIdleTime = $Self->{ConfigObject}->Get('SessionMaxIdleTime');

    # get config settings
    my $SortBy = $Self->{Config}->{SortBy} || 'UserFullname';

    # get current time-stamp
    my $Time = $Self->{TimeObject}->SystemTime();

    # check cache
    my $Online = $Self->{CacheObject}->Get(
        Type => 'Dashboard',
        Key  => $Self->{CacheKey},
    );

    # get session info
    my $CacheUsed = 1;
    if ( !$Online ) {

        $CacheUsed = 0;
        $Online    = {
            User => {
                Agent    => {},
                Customer => {},
            },
            UserCount => {
                Agent    => 0,
                Customer => 0,
            },
            UserData => {
                Agent    => {},
                Customer => {},
            },
        };

        # get database object
        my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

        # get session ids
        my @Sessions = $SessionObject->GetAllSessionIDs();

        # get user object
        my $UserObject = $Kernel::OM->Get('Kernel::System::User');

        SESSIONID:
        for my $SessionID (@Sessions) {

            next SESSIONID if !$SessionID;

            # get session data
            my %Data = $SessionObject->GetSessionIDData( SessionID => $SessionID );

            next SESSIONID if !%Data;
            next SESSIONID if !$Data{UserID};

            # use agent instead of user
            my %AgentData;
            if ( $Data{UserType} eq 'User' ) {
                $Data{UserType} = 'Agent';

                # get user data
                %AgentData = $UserObject->GetUserData(
                    UserID        => $Data{UserID},
                    NoOutOfOffice => 1,
                );
            }
            else {
                $Data{UserFullname}
                    ||= $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerName(
                    UserLogin => $Data{UserLogin},
                    );
            }

            # only show if not already shown
            next SESSIONID if $Online->{User}->{ $Data{UserType} }->{ $Data{UserID} };

            # check last request time / idle time out
            next SESSIONID if !$Data{UserLastRequest};
            next SESSIONID if $Data{UserLastRequest} + $SessionMaxIdleTime < $Time;

            # remember user and data
            $Online->{User}->{ $Data{UserType} }->{ $Data{UserID} } = $Data{$SortBy};
            $Online->{UserCount}->{ $Data{UserType} }++;
            $Online->{UserData}->{ $Data{UserType} }->{ $Data{UserID} } = { %Data, %AgentData };
        }
    }

    # set cache
    if ( !$CacheUsed && $Self->{Config}->{CacheTTLLocal} ) {
        $Self->{CacheObject}->Set(
            Type  => 'Dashboard',
            Key   => $Self->{CacheKey},
            Value => $Online,
            TTL   => $Self->{Config}->{CacheTTLLocal} * 60,
        );
    }

    # set css class
    my %Summary;
    $Summary{ $Self->{Filter} . '::Selected' } = 'Selected';

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # filter bar
    $LayoutObject->Block(
        Name => 'ContentSmallUserOnlineFilter',
        Data => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
            %{ $Online->{UserCount} },
            %Summary,
        },
    );

    # add page nav bar
    my $Total    = $Online->{UserCount}->{ $Self->{Filter} } || 0;
    my $LinkPage = 'Subaction=Element;Name=' . $Self->{Name} . ';Filter=' . $Self->{Filter} . ';';
    my %PageNav  = $LayoutObject->PageNavBar(
        StartHit       => $Self->{StartHit},
        PageShown      => $Self->{PageShown},
        AllHits        => $Total || 1,
        Action         => 'Action=' . $LayoutObject->{Action},
        Link           => $LinkPage,
        WindowSize     => 5,
        AJAXReplace    => 'Dashboard' . $Self->{Name},
        IDPrefix       => 'Dashboard' . $Self->{Name},
        KeepScriptTags => $Param{AJAX},
    );

    $LayoutObject->Block(
        Name => 'ContentSmallTicketGenericFilterNavBar',
        Data => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
            %PageNav,
        },
    );

    # show agent/customer
    my %OnlineUser = %{ $Online->{User}->{ $Self->{Filter} } };
    my %OnlineData = %{ $Online->{UserData}->{ $Self->{Filter} } };
    my $Count      = 0;
    my $Limit      = $LayoutObject->{ $Self->{PrefKey} } || $Self->{Config}->{Limit};

    # Check if agent has permission to start chats with the listed users
    my $EnableChat               = 1;
    my $ChatStartingAgentsGroup  = $Self->{ConfigObject}->Get('ChatEngine::PermissionGroup::ChatStartingAgents');
    my $ChatReceivingAgentsGroup = $Self->{ConfigObject}->Get('ChatEngine::PermissionGroup::ChatReceivingAgents');

    if (
        !$Self->{ConfigObject}->Get('ChatEngine::Active')
        || !defined $Self->{LayoutObject}->{"UserIsGroup[$ChatStartingAgentsGroup]"}
        || $Self->{LayoutObject}->{"UserIsGroup[$ChatStartingAgentsGroup]"} ne 'Yes'
        )
    {
        $EnableChat = 0;
    }
    if (
        $EnableChat
        && $Self->{Filter} eq 'Agent'
        && !$Self->{ConfigObject}->Get('ChatEngine::ChatDirection::AgentToAgent')
        )
    {
        $EnableChat = 0;
    }
    if (
        $EnableChat
        && $Self->{Filter} eq 'Customer'
        && !$Self->{ConfigObject}->Get('ChatEngine::ChatDirection::AgentToCustomer')
        )
    {
        $EnableChat = 0;
    }

    USERID:
    for my $UserID ( sort { $OnlineUser{$a} cmp $OnlineUser{$b} } keys %OnlineUser ) {

        $Count++;

        next USERID if !$UserID;
        next USERID if $Count < $Self->{StartHit};
        last USERID if $Count >= ( $Self->{StartHit} + $Self->{PageShown} );

        # extract user data
        my $UserData        = $OnlineData{$UserID};
        my $AgentEnableChat = 0;

        # we also need to check if the receiving agent has chat permissions
        if ( $EnableChat && $Self->{Filter} eq 'Agent' && $Self->{UserID} != $UserData->{UserID} ) {

            my %UserGroups = $Self->{GroupObject}->GroupMemberList(
                UserID => $UserData->{UserID},
                Type   => 'rw',
                Result => 'HASH',
            );

            my %UserGroupsReverse = reverse %UserGroups;
            $AgentEnableChat = $UserGroupsReverse{$ChatReceivingAgentsGroup} ? 1 : 0;
        }

        $LayoutObject->Block(
            Name => 'ContentSmallUserOnlineRow',
            Data => {
                %{$UserData},
                AgentEnableChat => $AgentEnableChat,
            },
        );

        if ( $Self->{Config}->{ShowEmail} ) {
            $LayoutObject->Block(
                Name => 'ContentSmallUserOnlineRowEmail',
                Data => $UserData,
            );
        }

        next USERID if !$UserData->{OutOfOffice};

        my $Start = sprintf(
            "%04d-%02d-%02d 00:00:00",
            $UserData->{OutOfOfficeStartYear}, $UserData->{OutOfOfficeStartMonth},
            $UserData->{OutOfOfficeStartDay}
        );
        my $TimeStart = $Self->{TimeObject}->TimeStamp2SystemTime(
            String => $Start,
        );
        my $End = sprintf(
            "%04d-%02d-%02d 23:59:59",
            $UserData->{OutOfOfficeEndYear}, $UserData->{OutOfOfficeEndMonth},
            $UserData->{OutOfOfficeEndDay}
        );
        my $TimeEnd = $Self->{TimeObject}->TimeStamp2SystemTime(
            String => $End,
        );

        next USERID if $TimeStart > $Time || $TimeEnd < $Time;

        $LayoutObject->Block(
            Name => 'ContentSmallUserOnlineRowOutOfOffice',
        );
    }

    if ( !%OnlineUser ) {
        $LayoutObject->Block(
            Name => 'ContentSmallUserOnlineNone',
        );
    }

    # check for refresh time
    my $Refresh = '';
    if ( $Self->{UserRefreshTime} ) {
        $Refresh = 60 * $Self->{UserRefreshTime};
        my $NameHTML = $Self->{Name};
        $NameHTML =~ s{-}{_}xmsg;
        $LayoutObject->Block(
            Name => 'ContentSmallUserOnlineRefresh',
            Data => {
                %{ $Self->{Config} },
                Name        => $Self->{Name},
                NameHTML    => $NameHTML,
                RefreshTime => $Refresh,
            },
        );
    }

    my $Content = $LayoutObject->Output(
        TemplateFile => 'AgentDashboardUserOnline',
        Data         => {
            %{ $Self->{Config} },
            Name => $Self->{Name},
        },
        KeepScriptTags => $Param{AJAX},
    );

    return $Content;
}

1;