#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use Getopt::Long;
use File::Path qw(make_path);
use File::Find;
use File::Copy;
use Cwd;

my $REPO_DIR = "/Users/SCoachbuilder/repos/ecl";
my $PATCH_FILE = "/Users/SCoachbuilder/repos/INVECL-11907.patch";
my $PREFIX="remotes\/origin\/";
my $TIME = time;
my $LOG_DIR = 'patch_log/';
my $LOG_FILE = 'patch.log';

my $branch = '';
my $working_dir = getcwd;

GetOptions(
    'b=s' => \$branch,
);

my $log_dir = "$LOG_DIR/$branch/$TIME/";

sub get_branches {
	my ($repo_dir) = @_;

	my $branches = `cd $repo_dir && git branch -a | grep 'remotes/origin/' | sed -e 's/^[[:space:]]*//' | sed -e 's|'$PREFIX'||g'`;
	my @branches = grep {
		$_ !~ /master/ && $_ !~ /HEAD/
	} split(/\n/, $branches);

	return \@branches;
}

sub limit_branches {
	my ($branches, $start_branch) = @_;

	### don't look for start branch if we didn't set one
	my $found_start_branch = $start_branch ? 0 : 1;

	my @branches_after_start_branch;
	foreach my $branch (@$branches) {
		if ($branch eq $start_branch) {
			$found_start_branch = 1;
		}
		next unless $found_start_branch;

		push(@branches_after_start_branch, $branch);
	}

	return \@branches_after_start_branch;
}

sub create_directory {
	my ($path) = @_;

	my @created;
	unless (-e $path and -d $path) {
		@created = make_path($path);
	}

	return \@created;
}

sub get_tracked_changes {
	my ($repo) = @_;

	### get changes that have modified or deleted prepended to them
	my $output = `cd $repo && git status | grep 'deleted\\|modified' | cut -c 14-`;

	my @tracked = split(/\n/, $output);

	return \@tracked;
}

sub get_untracked_changes {
	my ($repo) = @_;

	my $untracked = `cd $repo && git ls-files --others --exclude-standard`;
	#git ls-files --modified

	my @untracked = split(/\n/, $untracked);
	return \@untracked;
}

sub move_patch_files_to_dir {
	my ($untracked_files, $log_dir) = @_;

	my $patch_file_extensions = join(
		'|',
		map {
			'\.' . $_ . '$'
		} ('rej', 'orig')
	);

	my @patch_files = grep {
		$_ =~ /$patch_file_extensions/
	} @$untracked_files;

	foreach my $file (@patch_files) {
		move("$REPO_DIR/$file", "$log_dir") or die "The move operation failed: $!";

		logger("moved to log directory: $file\n");
	}

	return \@patch_files;
}

my $branches = get_branches($REPO_DIR);
$branches = limit_branches($branches, $branch);
print STDERR Dumper($branches);
#print STDERR join(' ', @$branches);
#exit;

foreach $branch (@$branches) {
	$log_dir = "$LOG_DIR/$branch/$TIME/";
	create_directory($log_dir);
	logger("log created at $log_dir\n");
	logger(`cd $REPO_DIR && git checkout master`);
	logger(`cd $REPO_DIR && git pull`);
	logger(`cd $REPO_DIR && git checkout $branch`);
	logger(`cd $REPO_DIR && git pull`);
	logger(`cd $REPO_DIR && patch -p1 < $PATCH_FILE 2>&1`);

	my $untracked_changes = get_untracked_changes($REPO_DIR);

	### Find patch's failed files and move those to the log dir
	move_patch_files_to_dir($untracked_changes, $log_dir);

	my $tracked = get_tracked_changes($REPO_DIR);
	logger("adding files:\n" . join('', map { "\t$_\n" } @$tracked));

	my $commit_files = join(' ', @$tracked);

	unless (scalar @$tracked) {
		logger("no files changed; exiting early\n");
		next;
	}

	logger(`cd $REPO_DIR && git add $commit_files`);

	my %changed_files = map {
		$_ => 1,
	} (
		'code/lib/eCarList/BLL/CRUD/Trade.pm',
		'code/lib/javascript/eCarList/App/Analytics/AppraisalPage.js',
		'code/lib/javascript/eCarList/App/Analytics/PricingPopup.js',
		'code/lib/javascript/eCarList/App/Analytics/PricingPopup/RetailFilters.js',
		'templates/admin/appraisal/appraisal_list_table.tmpl',
	);


	### bad = files that are not in our known good set
	my @bad = grep {
		!$changed_files{$_}
	} @$tracked;

	if (scalar @bad) {
		logger("found files that I'm not sure should be checked in\n");
		exit;
	}

	logger(`cd $REPO_DIR && git commit -m "fix devops merge issue with patch INVECL-11907.patch"`);
	logger(`cd $REPO_DIR && git push`);
}

sub logger {
	my ($string) = @_;

	my $log_file = $log_dir . 'output.log';

	print STDERR $string;

	open(my $log, '>>', $log_file) or die "Could not open file '$log_file' $!";
	print $log "$string";
	close $log;

	return;
}


