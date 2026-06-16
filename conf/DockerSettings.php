<?php
# DockerSettings.php — WikiTeq pattern
# Loads extensions/skins based on MW_LOAD_EXTENSIONS / MW_LOAD_SKINS env vars
# Append to LocalSettings.php: require_once "$IP/DockerSettings.php";

if ( !defined( 'MEDIAWIKI' ) ) { exit; }

const DOCKER_SKINS = [
    'chameleon',
    'MinervaNeue',
    'Timeless',
];

const DOCKER_EXTENSIONS = [
    'AdminLinks', 'AdvancedSearch', 'AJAXPoll', 'AntiSpoof', 'ApprovedRevs',
    'Arrays', 'BetaFeatures', 'CheckUser', 'CirrusSearch', 'CodeMirror',
    'CommonsMetadata', 'ConfirmAccount', 'ContactPage', 'DataTransfer',
    'Disambiguator', 'DismissableSiteNotice', 'DisplayTitle', 'Echo',
    'Elastica', 'EmbedVideo', 'ExternalData', 'Gadgets', 'GlobalNotice',
    'HTMLTags', 'IframePage', 'Interwiki', 'LabeledSectionTransclusion',
    'Lingo', 'Lockdown', 'Loops', 'MassMessage', 'MobileFrontend',
    'MsUpload', 'MultimediaViewer', 'MyVariables', 'Nuke', 'NumerAlpha',
    'OATHAuth', 'OpenGraphMeta', 'OpenIDConnect', 'PageForms', 'PageImages',
    'PageSchemas', 'PdfHandler', 'PluggableAuth', 'Popups', 'ReplaceText',
    'RevisionSlider', 'Scribunto', 'SecureLinkFixer', 'SelectCategory',
    'SemanticCompoundQueries', 'SemanticDrilldown', 'SemanticExtraSpecialProperties',
    'SemanticMediaWiki', 'SemanticResultFormats', 'SemanticScribunto',
    'SocialProfile', 'SubPageList', 'Thanks', 'TimedMediaHandler',
    'UniversalLanguageSelector', 'UploadWizard', 'UserMerge', 'VEForAll',
    'Variables', 'VisualEditor', 'VoteNY', 'WhoIsWatching', 'Widgets',
];

// Load skins from MW_LOAD_SKINS env
$skinsToLoad = array_filter( array_map( 'trim',
    explode( ',', getenv( 'MW_LOAD_SKINS' ) ?: '' ) ) );
foreach ( $skinsToLoad as $skin ) {
    if ( in_array( $skin, DOCKER_SKINS ) ) {
        wfLoadSkin( $skin );
    }
}

// Load extensions from MW_LOAD_EXTENSIONS env
$extensionsToLoad = array_filter( array_map( 'trim',
    explode( ',', getenv( 'MW_LOAD_EXTENSIONS' ) ?: '' ) ) );
foreach ( $extensionsToLoad as $ext ) {
    if ( in_array( $ext, DOCKER_EXTENSIONS ) ) {
        wfLoadExtension( $ext );
    }
}
