#Requires -Version 5.1
<#
.SYNOPSIS
    JDS-Repair-Toolkit - Outil de Dépannage Windows Unifié
    Interface WPF moderne pour le nettoyage, diagnostic, réparation et intégration d'outils.
#>

[CmdletBinding()]
param()

# Assurer l'exécution en tant qu'administrateur
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[>>] Relancement avec privilèges Administrateur..." -ForegroundColor Yellow
    $scriptPath = $MyInvocation.MyCommand.Path
    if ($scriptPath) {
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    } else {
        # Si exécuté via irm | iex, relancer l'expression avec prompt UAC
        Start-Process powershell.exe -ArgumentList "-ExecutionPolicy Bypass -Command `"& { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; iex (irm 'https://raw.githubusercontent.com/john2k/JDS-Repair-Toolkit/main/JDS-Repair-Toolkit.ps1') }`"" -Verb RunAs
    }
    exit
}

# Charger les assemblys requises pour WPF
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms, System.Drawing

# Créer un alias ou une fonction de secours pour Start-ThreadJob s'il n'est pas disponible (ex: PowerShell 5.1 sans module ThreadJob)
if (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
    function Start-ThreadJob {
        param(
            [scriptblock]$ScriptBlock,
            [object[]]$ArgumentList = @()
        )
        $ps = [PowerShell]::Create()
        $ps.AddCommand("Invoke-Command").AddParameter("ScriptBlock", $ScriptBlock) | Out-Null
        if ($ArgumentList) {
            $ps.AddParameter("ArgumentList", $ArgumentList) | Out-Null
        }
        $asyncResult = $ps.BeginInvoke()
        [PSCustomObject]@{
            PSType             = "RunspaceJob"
            PowerShellInstance = $ps
            AsyncResult        = $asyncResult
        }
    }

    function Receive-Job {
        param(
            [Parameter(ValueFromPipeline = $true)]
            [object]$Job,
            [switch]$Wait,
            [switch]$AutoRemoveJob
        )
        process {
            if ($Job -and $Job.PSType -eq "RunspaceJob") {
                if ($Wait) {
                    $Job.AsyncResult.AsyncWaitHandle.WaitOne() | Out-Null
                }
                $results = $Job.PowerShellInstance.EndInvoke($Job.AsyncResult)
                $Job.PowerShellInstance.Dispose()
                return $results
            } else {
                Microsoft.PowerShell.Core\Receive-Job -Job $Job -Wait:$Wait -AutoRemoveJob:$AutoRemoveJob
            }
        }
    }
}

# Répertoire de travail
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { $pwd.Path }
$ConfigFile = Join-Path $ScriptDir "JDS-Repair-Toolkit-Config.json"

# Charger ou définir la configuration initiale
$Config = @{
    ToolsPath = ""
}
if (Test-Path $ConfigFile) {
    try {
        $Config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } catch {}
}

# Détecter si les outils sont présents localement par défaut
if ([string]::IsNullOrEmpty($Config.ToolsPath)) {
    if (Test-Path (Join-Path $ScriptDir "FAB")) {
        $Config.ToolsPath = $ScriptDir
    }
}

# Chemins réseau pré-définis
$PredefinedPaths = @(
    "\\10.1.1.201\Clients\tools",
    "\\11.11.11.223\Tech\jds-toolbox",
    "\\192.168.1.100\Shared\JDS-Toolkit",
    "\\10.0.0.5\Public\Rescue-Tools"
)

# Code XAML pour l'interface graphique
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="JDS Repair Toolkit - Console de Dépannage v1.0" Height="680" Width="1000"
        WindowStartupLocation="CenterScreen" Background="#1E1E24" ResizeMode="CanMinimize">
    <Window.Resources>
        <!-- Styles des boutons de la barre latérale -->
        <Style x:Key="SidebarButton" TargetType="Button">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Foreground" Value="#CCCCCC"/>
            <Setter Property="FontSize" Value="14"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="15,12,15,12"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="HorizontalContentAlignment" Value="Left"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#252530"/>
                    <Setter Property="Foreground" Value="#00D2C4"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <!-- Styles des boutons standards -->
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#00adb5"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Padding" Value="12,8,12,8"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#00d2c4"/>
                </Trigger>
            </Style.Triggers>
        </Style>
        <Style x:Key="SecondaryButton" TargetType="Button">
            <Setter Property="Background" Value="#2A2A35"/>
            <Setter Property="Foreground" Value="#E0E0E0"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="BorderBrush" Value="#444455"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12,8,12,8"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#353545"/>
                </Trigger>
            </Style.Triggers>
        </Style>
    </Window.Resources>
    
    <Grid>
        <!-- Contenu Principal -->
        <Grid Name="MainAppLayout" Visibility="Collapsed">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="220"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>

            <!-- Sidebar -->
            <Grid Grid.Column="0" Background="#111115">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>

                <!-- Titre / Logo -->
                <StackPanel Grid.Row="0" Margin="15,20,15,20">
                    <TextBlock Text="JDS REPAIR" FontSize="20" FontWeight="Bold" Foreground="#00D2C4" HorizontalAlignment="Center"/>
                    <TextBlock Text="TOOLKIT" FontSize="12" FontWeight="SemiBold" Foreground="#888888" HorizontalAlignment="Center"/>
                </StackPanel>

                <!-- Menu de navigation -->
                <StackPanel Grid.Row="1">
                    <Button Name="BtnTabDiag" Style="{StaticResource SidebarButton}" Content="🩺  Diagnostics"/>
                    <Button Name="BtnTabClean" Style="{StaticResource SidebarButton}" Content="🧹  Nettoyage"/>
                    <Button Name="BtnTabRepair" Style="{StaticResource SidebarButton}" Content="🛠️  Réparations"/>
                    <Button Name="BtnTabApps" Style="{StaticResource SidebarButton}" Content="🦠  Scanners &amp; Désins."/>
                    <Button Name="BtnTabBackup" Style="{StaticResource SidebarButton}" Content="💾  Sauvegarde (FAB)"/>
                    <Button Name="BtnTabOptane" Style="{StaticResource SidebarButton}" Content="⚙️  Pilotes / Optane"/>
                    <Button Name="BtnTabTools" Style="{StaticResource SidebarButton}" Content="🧰  Outils Tiers"/>
                    <Button Name="BtnTabDownloads" Style="{StaticResource SidebarButton}" Content="📥  Téléchargements"/>
                </StackPanel>

                <!-- Status / Version footer -->
                <StackPanel Grid.Row="2" Margin="15" Orientation="Vertical">
                    <TextBlock Name="TxtStatusPath" Text="Dossier : Local" FontSize="10" Foreground="#666666" TextTrimming="CharacterEllipsis"/>
                    <Button Name="BtnChangePath" Content="Modifier le chemin" Background="Transparent" Foreground="#00adb5" BorderThickness="0" FontSize="10" HorizontalAlignment="Left" Cursor="Hand" Margin="0,5,0,0"/>
                </StackPanel>
            </Grid>

            <!-- Zone de contenu principale -->
            <Grid Grid.Column="1" Margin="25">
                <!-- Onglet DIAGNOSTICS -->
                <Grid Name="GridDiag" Visibility="Visible">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Diagnostic &amp; Informations Système" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <StackPanel>
                                    <TextBlock Text="🖥️ Système" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Name="TxtDiagOS" Text="OS : Détection en cours..." Foreground="White" Margin="0,2,0,2"/>
                                    <TextBlock Name="TxtDiagCPU" Text="Processeur : Détection en cours..." Foreground="White" Margin="0,2,0,2"/>
                                    <TextBlock Name="TxtDiagRAM" Text="Mémoire RAM : Détection en cours..." Foreground="White" Margin="0,2,0,2"/>
                                    <TextBlock Name="TxtDiagMB" Text="Carte Mère : Détection en cours..." Foreground="White" Margin="0,2,0,2"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <StackPanel>
                                    <TextBlock Text="🛡️ Sécurité &amp; Antivirus" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Name="TxtDiagAV" Text="Antivirus détectés : Recherche..." Foreground="White"/>
                                </StackPanel>
                            </Border>

                            <Border Background="#252530" CornerRadius="5" Padding="15">
                                <StackPanel>
                                    <TextBlock Text="💾 Stockage &amp; SMART (Physique)" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Name="TxtDiagDisks" Text="Analyse des disques..." Foreground="White" FontFamily="Consolas"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                    
                    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,15,0,0">
                        <Button Name="BtnRefreshDiag" Style="{StaticResource ModernButton}" Content="Rafraîchir les informations" Width="180"/>
                    </StackPanel>
                </Grid>

                <!-- Onglet NETTOYAGE -->
                <Grid Name="GridClean" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Nettoyage du Système" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <StackPanel Grid.Row="1">
                        <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                            <StackPanel>
                                <TextBlock Text="🧹 Fichiers Temporaires &amp; Caches" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                <TextBlock Text="Cette option supprime les fichiers temporaires de Windows, le cache de Windows Update et les caches des principaux navigateurs internet." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,15"/>
                                <CheckBox Name="ChkCleanTemp" Content="Fichiers Temporaires Windows (%TEMP%)" Foreground="White" IsChecked="True" Margin="0,0,0,8"/>
                                <CheckBox Name="ChkCleanUpdate" Content="Cache Windows Update (SoftwareDistribution)" Foreground="White" IsChecked="True" Margin="0,0,0,8"/>
                                <CheckBox Name="ChkCleanBrowsers" Content="Caches navigateurs (Chrome, Edge, Firefox)" Foreground="White" IsChecked="True" Margin="0,0,0,15"/>
                                <Button Name="BtnStartClean" Style="{StaticResource ModernButton}" Content="Lancer le Nettoyage" HorizontalAlignment="Left" Width="180"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#252530" CornerRadius="5" Padding="15">
                            <StackPanel>
                                <TextBlock Text="📦 Bloatware &amp; Applications indésirables" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                <TextBlock Text="Ouvrir le panneau classique pour désinstaller rapidement les programmes installés par défaut ou superflus." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,15"/>
                                <Button Name="BtnOpenAppwiz" Style="{StaticResource SecondaryButton}" Content="Ouvrir Programmes et Fonctionnalités" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>

                    <!-- Terminal de logs pour le nettoyage -->
                    <TextBox Grid.Row="2" Name="TxtLogClean" Height="150" Background="#121216" Foreground="#00FF00" FontFamily="Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" Text="En attente du lancement..." BorderThickness="1" BorderBrush="#333333"/>
                </Grid>

                <!-- Onglet REPARATIONS -->
                <Grid Name="GridRepair" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Outils de Réparation Intégrés" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <WrapPanel ItemWidth="350" ItemHeight="160">
                            <!-- SFC / DISM -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="5">
                                <StackPanel>
                                    <TextBlock Text="🛠️ SFC &amp; DISM" FontSize="15" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <TextBlock Text="Répare l'intégrité des fichiers système et du magasin de composants Windows." Foreground="#AAAAAA" FontSize="11" TextWrapping="Wrap" Height="40"/>
                                    <StackPanel Orientation="Horizontal" Margin="0,10,0,0">
                                        <Button Name="BtnRunSFC" Style="{StaticResource ModernButton}" Content="Lancer SFC" Width="100" Margin="0,0,10,0"/>
                                        <Button Name="BtnRunDISM" Style="{StaticResource ModernButton}" Content="Lancer DISM" Width="100"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <!-- Windows Update Repair -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="5">
                                <StackPanel>
                                    <TextBlock Text="🔄 Réparation Windows Update" FontSize="15" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <TextBlock Text="Réinitialise complètement les services et le dossier temporaire de mise à jour Windows." Foreground="#AAAAAA" FontSize="11" TextWrapping="Wrap" Height="40"/>
                                    <Button Name="BtnFixWU" Style="{StaticResource ModernButton}" Content="Réparer Windows Update" Width="180" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>

                            <!-- Network Reset -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="5">
                                <StackPanel>
                                    <TextBlock Text="🌐 Réinitialisation Réseau" FontSize="15" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <TextBlock Text="Vide le DNS, réinitialise Winsock et TCP/IP pour régler les soucis de connexion." Foreground="#AAAAAA" FontSize="11" TextWrapping="Wrap" Height="40"/>
                                    <Button Name="BtnResetNetwork" Style="{StaticResource ModernButton}" Content="Réinitialiser le Réseau" Width="180" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>

                            <!-- Planificateur de tâches -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="5">
                                <StackPanel>
                                    <TextBlock Text="📅 Tâches Suspectes" FontSize="15" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <TextBlock Text="Recherche les tâches planifiées ajoutées récemment ou potentiellement indésirables." Foreground="#AAAAAA" FontSize="11" TextWrapping="Wrap" Height="40"/>
                                    <Button Name="BtnAuditTasks" Style="{StaticResource ModernButton}" Content="Analyser les Tâches" Width="180" Margin="0,10,0,0"/>
                                </StackPanel>
                            </Border>
                        </WrapPanel>
                    </ScrollViewer>

                    <!-- Terminal de logs pour les réparations -->
                    <TextBox Grid.Row="2" Name="TxtLogRepair" Height="180" Background="#121216" Foreground="#00FF00" FontFamily="Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" Text="Prêt à lancer..." BorderThickness="1" BorderBrush="#333333"/>
                </Grid>

                <!-- Onglet SAUVEGARDE -->
                <Grid Name="GridBackup" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Sauvegarde et Restauration" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <StackPanel Grid.Row="1">
                        <Border Background="#252530" CornerRadius="5" Padding="20" Margin="0,0,0,20">
                            <StackPanel>
                                <TextBlock Text="💾 Fab's AutoBackup 7 Pro" FontSize="18" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                <TextBlock Text="Permet de sauvegarder ou restaurer automatiquement les documents, images, favoris et boîtes mails de tous les utilisateurs." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,15"/>
                                
                                <Grid Margin="0,0,0,15">
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="Auto"/>
                                        <ColumnDefinition Width="*"/>
                                    </Grid.ColumnDefinitions>
                                    <TextBlock Grid.Column="0" Text="Statut : " Foreground="White" FontWeight="Bold"/>
                                    <TextBlock Grid.Column="1" Name="TxtFABStatus" Text="Non détecté" Foreground="#FF5555" Margin="5,0,0,0"/>
                                </Grid>

                                <Button Name="BtnRunFAB" Style="{StaticResource ModernButton}" Content="Lancer Fab's AutoBackup" HorizontalAlignment="Left" Width="200" IsEnabled="False"/>
                            </StackPanel>
                        </Border>

                        <Border Background="#252530" CornerRadius="5" Padding="20">
                            <StackPanel>
                                <TextBlock Text="📦 Sauvegarde Rapide Alternative (Native)" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                <TextBlock Text="Sauvegarde les dossiers essentiels de l'utilisateur actif vers un répertoire sélectionné." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,15"/>
                                <Button Name="BtnRunNativeBackup" Style="{StaticResource SecondaryButton}" Content="Lancer la Sauvegarde Native" HorizontalAlignment="Left"/>
                            </StackPanel>
                        </Border>
                    </StackPanel>
                </Grid>

                <!-- Onglet OPTANE -->
                <Grid Name="GridOptane" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Injection de Pilotes RST / Optane" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <StackPanel>
                                    <TextBlock Text="⚙️ Préparation du disque cible" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Text="Indiquez la lettre de la partition Windows cible où injecter les pilotes (ex: C, D, E)." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,10"/>
                                    <StackPanel Orientation="Horizontal">
                                        <TextBlock Text="Lettre de lecteur :" Foreground="White" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                        <TextBox Name="TxtOptaneDrive" Width="60" Height="25" Text="C" HorizontalAlignment="Left" Background="#1E1E24" Foreground="White" VerticalContentAlignment="Center" HorizontalContentAlignment="Center" BorderBrush="#444455"/>
                                    </StackPanel>
                                </StackPanel>
                            </Border>

                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <StackPanel>
                                    <TextBlock Text="📂 Dossier contenant les Pilotes Intel RST/Optane" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Text="Spécifiez le chemin d'accès contenant les pilotes .inf" Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,10"/>
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBox Grid.Column="0" Name="TxtOptaneDriverPath" Height="25" Background="#1E1E24" Foreground="White" VerticalContentAlignment="Center" BorderBrush="#444455" Margin="0,0,10,0"/>
                                        <Button Grid.Column="1" Name="BtnBrowseOptaneDrivers" Style="{StaticResource SecondaryButton}" Content="Parcourir" Height="25" Padding="10,0,10,0"/>
                                    </Grid>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>

                    <StackPanel Grid.Row="2" Orientation="Vertical">
                        <TextBox Name="TxtLogOptane" Height="150" Background="#121216" Foreground="#00FF00" FontFamily="Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" Text="Prêt pour l'injection..." BorderThickness="1" BorderBrush="#333333" Margin="0,0,0,10"/>
                        <Button Name="BtnRunOptaneInjection" Style="{StaticResource ModernButton}" Content="Injecter les Pilotes avec DISM" HorizontalAlignment="Right" Width="220"/>
                    </StackPanel>
                </Grid>

                <!-- Onglet OUTILS TIERS -->
                <Grid Name="GridTools" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Outils et Utilitaires Tiers" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <!-- Tron Script -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="🚀 Tron Script" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                        <TextBlock Text="Script d'automatisation complet pour désinfecter, nettoyer et optimiser Windows en profondeur. Idéal pour les machines très compromises." Foreground="#AAAAAA" TextWrapping="Wrap" FontSize="12"/>
                                        <TextBlock Name="TxtTronStatus" Text="Statut : Non détecté" Foreground="#FF5555" Margin="0,5,0,0" FontSize="11"/>
                                    </StackPanel>
                                    <Button Grid.Column="1" Name="BtnRunTron" Style="{StaticResource ModernButton}" Content="Lancer Tron" Width="130" IsEnabled="False" VerticalAlignment="Center" Margin="15,0,0,0"/>
                                </Grid>
                            </Border>

                            <!-- Windows Repair Unlocked (All In One) -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="⚙️ Tweaking.com Windows Repair Unlocked" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                        <TextBlock Text="Restaure les paramètres par défaut de Windows (registre, permissions de fichiers, pare-feu, hôtes, etc.)." Foreground="#AAAAAA" TextWrapping="Wrap" FontSize="12"/>
                                        <TextBlock Name="TxtTweakingStatus" Text="Statut : Non détecté" Foreground="#FF5555" Margin="0,5,0,0" FontSize="11"/>
                                    </StackPanel>
                                    <Button Grid.Column="1" Name="BtnRunTweaking" Style="{StaticResource ModernButton}" Content="Lancer Repair" Width="130" IsEnabled="False" VerticalAlignment="Center" Margin="15,0,0,0"/>
                                </Grid>
                            </Border>

                            <!-- Portable Windows Repair Toolbox -->
                            <Border Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,0,15">
                                <Grid>
                                    <Grid.ColumnDefinitions>
                                        <ColumnDefinition Width="*"/>
                                        <ColumnDefinition Width="Auto"/>
                                    </Grid.ColumnDefinitions>
                                    <StackPanel Grid.Column="0">
                                        <TextBlock Text="🧰 Portable Windows Repair Toolbox" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                        <TextBlock Text="Suite d'utilitaires portables téléchargés à la demande pour diagnostiquer et corriger divers problèmes." Foreground="#AAAAAA" TextWrapping="Wrap" FontSize="12"/>
                                        <TextBlock Name="TxtPWRTStatus" Text="Statut : Non détecté" Foreground="#FF5555" Margin="0,5,0,0" FontSize="11"/>
                                    </StackPanel>
                                    <Button Grid.Column="1" Name="BtnRunPWRT" Style="{StaticResource ModernButton}" Content="Lancer Toolbox" Width="130" IsEnabled="False" VerticalAlignment="Center" Margin="15,0,0,0"/>
                                </Grid>
                            </Border>
                            
                            <!-- Services Windows -->
                            <Border Background="#252530" CornerRadius="5" Padding="15">
                                <StackPanel>
                                    <TextBlock Text="⚙️ Gestionnaire de Services Rapide" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,10"/>
                                    <TextBlock Text="Permet d'ouvrir le gestionnaire de services système directement." Foreground="#AAAAAA" TextWrapping="Wrap" Margin="0,0,0,10"/>
                                    <Button Name="BtnOpenServices" Style="{StaticResource SecondaryButton}" Content="Ouvrir services.msc" HorizontalAlignment="Left"/>
                                </StackPanel>
                            </Border>
                        </StackPanel>
                    </ScrollViewer>
                </Grid>

                <!-- Onglet SCANNERS & DESINSTALL. -->
                <Grid Name="GridApps" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    <TextBlock Grid.Row="0" Text="Scanners Jetables &amp; Désinstallation" FontSize="22" FontWeight="Bold" Foreground="White" Margin="0,0,0,15"/>
                    
                    <Grid Grid.Row="1">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="380"/>
                            <ColumnDefinition Width="*"/>
                        </Grid.ColumnDefinitions>

                        <!-- Scanners Jetables (Left) -->
                        <Border Grid.Column="0" Background="#252530" CornerRadius="5" Padding="15" Margin="0,0,10,0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                </Grid.RowDefinitions>
                                <StackPanel Grid.Row="0">
                                    <TextBlock Text="🦠 Scanners Jetables" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <TextBlock Text="Télécharge, lance et supprime automatiquement l'exécutable à la fermeture pour laisser le PC propre." Foreground="#AAAAAA" FontSize="11" TextWrapping="Wrap" Margin="0,0,0,15"/>
                                </StackPanel>
                                <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto">
                                    <StackPanel>
                                        <!-- KVRT -->
                                        <Border Background="#1E1E24" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0">
                                                    <TextBlock Text="Kaspersky (KVRT)" FontWeight="Bold" Foreground="White"/>
                                                    <TextBlock Text="Désinfection complète sans installation" Foreground="#888888" FontSize="10"/>
                                                </StackPanel>
                                                <Button Grid.Column="1" Name="BtnRunKVRT" Style="{StaticResource ModernButton}" Content="Lancer" Width="70" Height="25" Padding="0"/>
                                            </Grid>
                                        </Border>
                                        
                                        <!-- AdwCleaner -->
                                        <Border Background="#1E1E24" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0">
                                                    <TextBlock Text="AdwCleaner" FontWeight="Bold" Foreground="White"/>
                                                    <TextBlock Text="Suppression adware et barres d'outils" Foreground="#888888" FontSize="10"/>
                                                </StackPanel>
                                                <Button Grid.Column="1" Name="BtnRunAdw" Style="{StaticResource ModernButton}" Content="Lancer" Width="70" Height="25" Padding="0"/>
                                            </Grid>
                                        </Border>

                                        <!-- ESET Online Scanner -->
                                        <Border Background="#1E1E24" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0">
                                                    <TextBlock Text="ESET Online Scanner" FontWeight="Bold" Foreground="White"/>
                                                    <TextBlock Text="Scanner cloud ESET puissant" Foreground="#888888" FontSize="10"/>
                                                </StackPanel>
                                                <Button Grid.Column="1" Name="BtnRunEset" Style="{StaticResource ModernButton}" Content="Lancer" Width="70" Height="25" Padding="0"/>
                                            </Grid>
                                        </Border>

                                        <!-- RogueKiller -->
                                        <Border Background="#1E1E24" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0">
                                                    <TextBlock Text="RogueKiller (Portable)" FontWeight="Bold" Foreground="White"/>
                                                    <TextBlock Text="Détection avancée des malwares et rootkits" Foreground="#888888" FontSize="10"/>
                                                </StackPanel>
                                                <Button Grid.Column="1" Name="BtnRunRogue" Style="{StaticResource ModernButton}" Content="Lancer" Width="70" Height="25" Padding="0"/>
                                            </Grid>
                                        </Border>

                                        <!-- Malwarebytes -->
                                        <Border Background="#1E1E24" CornerRadius="4" Padding="10" Margin="0,0,0,10">
                                            <Grid>
                                                <Grid.ColumnDefinitions>
                                                    <ColumnDefinition Width="*"/>
                                                    <ColumnDefinition Width="Auto"/>
                                                </Grid.ColumnDefinitions>
                                                <StackPanel Grid.Column="0">
                                                    <TextBlock Text="Malwarebytes (Offline)" FontWeight="Bold" Foreground="White"/>
                                                    <TextBlock Text="Installateur hors-ligne Malwarebytes" Foreground="#888888" FontSize="10"/>
                                                </StackPanel>
                                                <Button Grid.Column="1" Name="BtnRunMBAM" Style="{StaticResource ModernButton}" Content="Lancer" Width="70" Height="25" Padding="0"/>
                                            </Grid>
                                        </Border>
                                    </StackPanel>
                                </ScrollViewer>
                            </Grid>
                        </Border>

                        <!-- Désinstalleur (Right) -->
                        <Border Grid.Column="1" Background="#252530" CornerRadius="5" Padding="15" Margin="10,0,0,0">
                            <Grid>
                                <Grid.RowDefinitions>
                                    <RowDefinition Height="Auto"/>
                                    <RowDefinition Height="*"/>
                                    <RowDefinition Height="Auto"/>
                                </Grid.RowDefinitions>
                                <StackPanel Grid.Row="0" Margin="0,0,0,10">
                                    <TextBlock Text="🗑️ Désinstalleur Express" FontSize="16" FontWeight="Bold" Foreground="#00D2C4" Margin="0,0,0,5"/>
                                    <!-- Search box -->
                                    <Grid Margin="0,5,0,5">
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBox Grid.Column="0" Name="TxtSearchApps" Height="25" Background="#1E1E24" Foreground="White" VerticalContentAlignment="Center" BorderBrush="#444455" Padding="5,0,5,0"/>
                                        <Button Grid.Column="1" Name="BtnRefreshApps" Style="{StaticResource SecondaryButton}" Content="Rafraîchir" Height="25" Margin="10,0,0,0" Padding="10,0,10,0"/>
                                    </Grid>
                                </StackPanel>

                                <!-- List of apps -->
                                <ListBox Grid.Row="1" Name="LstInstalledApps" Background="#1E1E24" Foreground="White" BorderBrush="#444455" Margin="0,0,0,10"/>

                                <Button Grid.Row="2" Name="BtnUninstallApp" Style="{StaticResource ModernButton}" Content="Désinstaller le programme sélectionné" HorizontalAlignment="Right" Width="260"/>
                            </Grid>
                        </Border>
                    </Grid>

                    <!-- Terminal de logs pour les applications -->
                    <TextBox Grid.Row="2" Name="TxtLogApps" Height="100" Background="#121216" Foreground="#00FF00" FontFamily="Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto" AcceptsReturn="True" Text="Prêt..." BorderThickness="1" BorderBrush="#333333" Margin="0,15,0,0"/>
                </Grid>

                <!-- Onglet TELECHARGEMENTS PERSISTANTS -->
                <Grid Name="GridDownloads" Visibility="Collapsed">
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>
                    
                    <!-- En-tête -->
                    <Grid Grid.Row="0" Margin="0,0,0,15">
                        <Grid.ColumnDefinitions>
                            <ColumnDefinition Width="*"/>
                            <ColumnDefinition Width="Auto"/>
                        </Grid.ColumnDefinitions>
                        <StackPanel Grid.Column="0">
                            <TextBlock Text="Gestionnaire de Téléchargements" FontSize="22" FontWeight="Bold" Foreground="White"/>
                            <TextBlock Text="Téléchargez et mettez à jour de façon persistante vos outils dans votre dossier de boîte à outils." Foreground="#AAAAAA" FontSize="11" Margin="0,5,0,0"/>
                        </StackPanel>
                        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
                            <Button Name="BtnOpenDownloadLog" Style="{StaticResource SecondaryButton}" Content="📝 Voir le Log" Height="30" Padding="15,0,15,0" Margin="0,0,10,0"/>
                            <Button Name="BtnRefreshDownloads" Style="{StaticResource SecondaryButton}" Content="🔄 Rafraîchir les versions" Height="30" Padding="15,0,15,0"/>
                        </StackPanel>
                    </Grid>

                    <!-- Liste des outils -->
                    <ListBox Grid.Row="1" Name="LstDownloads" Background="#1E1E24" BorderBrush="#444455" BorderThickness="1" Padding="5"/>

                    <!-- Barre de progression de téléchargement -->
                    <Border Grid.Row="2" Background="#252530" CornerRadius="5" Padding="15" Margin="0,15,0,0">
                        <Grid>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>
                                <RowDefinition Height="Auto"/>
                            </Grid.RowDefinitions>
                            
                            <Grid Grid.Row="0" Margin="0,0,0,8">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBlock Grid.Column="0" Name="TxtProgressStatus" Text="Sélectionnez un outil pour démarrer..." Foreground="#CCCCCC" FontSize="12"/>
                                <TextBlock Grid.Column="1" Name="TxtProgressSpeed" Text="" Foreground="#00D2C4" FontSize="12" FontWeight="Bold"/>
                            </Grid>

                            <ProgressBar Grid.Row="1" Name="ProgressDownload" Height="15" Background="#1A1A22" Foreground="#00D2C4" BorderThickness="0"/>
                        </Grid>
                    </Border>
                </Grid>
            </Grid>
        </Grid>

        <!-- Overlay de sélection de chemin initial -->
        <Grid Name="PathSelectorOverlay" Visibility="Visible" Background="#16161D">
            <Border Width="600" Height="480" Background="#1E1E24" CornerRadius="8" Padding="25" VerticalAlignment="Center" HorizontalAlignment="Center" BorderBrush="#00adb5" BorderThickness="1">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto"/>
                        <RowDefinition Height="*"/>
                        <RowDefinition Height="Auto"/>
                    </Grid.RowDefinitions>

                    <StackPanel Grid.Row="0" Margin="0,0,0,15">
                        <TextBlock Text="Sélection de la Boîte à Outils" FontSize="20" FontWeight="Bold" Foreground="#00D2C4"/>
                        <TextBlock Text="Le toolkit doit localiser le répertoire contenant les dossiers d'outils tiers (FAB, Tron, optane-script, etc.)." Foreground="#AAAAAA" FontSize="12" Margin="0,5,0,0" TextWrapping="Wrap"/>
                    </StackPanel>

                    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Margin="0,5,0,15">
                        <StackPanel>
                            <TextBlock Text="📂 Sélectionner un chemin réseau configuré :" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                            <!-- Liste des chemins réseau préconfigurés -->
                            <ListBox Name="LstPredefinedPaths" Background="#252530" Foreground="White" BorderBrush="#444455" Height="100" Margin="0,0,0,15"/>

                            <TextBlock Text="📂 Ou saisir un chemin personnalisé :" FontWeight="Bold" Foreground="White" Margin="0,0,0,8"/>
                            <Grid Margin="0,0,0,15">
                                <Grid.ColumnDefinitions>
                                    <ColumnDefinition Width="*"/>
                                    <ColumnDefinition Width="Auto"/>
                                </Grid.ColumnDefinitions>
                                <TextBox Grid.Column="0" Name="TxtCustomPath" Height="30" Background="#252530" Foreground="White" VerticalContentAlignment="Center" BorderBrush="#444455" Padding="5"/>
                                <Button Grid.Column="1" Name="BtnBrowsePath" Style="{StaticResource SecondaryButton}" Content="Parcourir..." Height="30" Margin="10,0,0,0" Padding="15,0,15,0"/>
                            </Grid>
                            
                            <CheckBox Name="ChkSaveConfig" Content="Sauvegarder ce chemin pour les prochains lancements" Foreground="White" IsChecked="True"/>
                        </StackPanel>
                    </ScrollViewer>

                    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="BtnCancelPath" Style="{StaticResource SecondaryButton}" Content="Ignorer (Outils désactivés)" Margin="0,0,10,0"/>
                        <Button Name="BtnConfirmPath" Style="{StaticResource ModernButton}" Content="Valider le chemin et Continuer" Padding="20,8,20,8"/>
                    </StackPanel>
                </Grid>
            </Border>
        </Grid>
    </Grid>
</Window>
"@

# Nettoyage et chargement du XAML
$xaml.Window.RemoveAttribute("x:Class")
$reader = New-Object System.Xml.XmlNodeReader $xaml
$Form = [Windows.Markup.XamlReader]::Load($reader)

# Liaison des contrôles WPF dans des variables PowerShell globales
$xaml.SelectNodes("//*[@Name]") | ForEach-Object {
    Set-Variable -Name "WPF_$($_.Name)" -Value $Form.FindName($_.Name) -Scope Global
}

# Charger les chemins prédéfinis dans la liste
$PredefinedPaths | ForEach-Object { [void]$WPF_LstPredefinedPaths.Items.Add($_) }

# Fonction de mise à jour des statuts des outils tiers
function Update-ToolStatuses {
    param([string]$Path)

    if ([string]::IsNullOrEmpty($Path)) {
        $WPF_TxtStatusPath.Text = "Mode local : Outils désactivés"
        return
    }

    $WPF_TxtStatusPath.Text = "Dossier : $Path"

    # Vérification de Fab's AutoBackup
    $fabExe = Join-Path $Path "FAB\AutoBackup7Pro.exe"
    if (Test-Path $fabExe) {
        $WPF_TxtFABStatus.Text = "Détecté ($fabExe)"
        $WPF_TxtFABStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $WPF_BtnRunFAB.IsEnabled = $true
    } else {
        $WPF_TxtFABStatus.Text = "Non détecté dans $Path\FAB\"
        $WPF_TxtFABStatus.Foreground = [System.Windows.Media.Brushes]::Red
        $WPF_BtnRunFAB.IsEnabled = $false
    }

    # Vérification de Tron Script
    $tronDir = Get-ChildItem -Path $Path -Directory -Filter "Tron*" -ErrorAction SilentlyContinue | Select-Object -First 1
    $tronBat = $null
    if ($tronDir) {
        $tronBat = Join-Path $tronDir.FullName "tron\tron.bat"
    }
    if ($tronBat -and (Test-Path $tronBat)) {
        $WPF_TxtTronStatus.Text = "Détecté ($tronBat)"
        $WPF_TxtTronStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $WPF_BtnRunTron.IsEnabled = $true
    } else {
        $WPF_TxtTronStatus.Text = "Non détecté dans $Path\Tron*"
        $WPF_TxtTronStatus.Foreground = [System.Windows.Media.Brushes]::Red
        $WPF_BtnRunTron.IsEnabled = $false
    }

    # Vérification de Windows Repair
    $repairDir = Get-ChildItem -Path $Path -Directory -Filter "*Repair*" -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Name -match "Windows Repair Unlocked" } | Select-Object -First 1
    $repairExe = $null
    if ($repairDir) {
        $repairExe = Get-ChildItem -Path $repairDir.FullName -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -match "Windows Repair" -or $_.Name -match "Repair_Windows" } | Select-Object -First 1
    }
    if ($repairExe -and (Test-Path $repairExe.FullName)) {
        $WPF_TxtTweakingStatus.Text = "Détecté ($($repairExe.FullName))"
        $WPF_TxtTweakingStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $WPF_BtnRunTweaking.IsEnabled = $true
    } else {
        $WPF_TxtTweakingStatus.Text = "Non détecté (Windows Repair Unlocked)"
        $WPF_TxtTweakingStatus.Foreground = [System.Windows.Media.Brushes]::Red
        $WPF_BtnRunTweaking.IsEnabled = $false
    }

    # Vérification de Portable Windows Repair Toolbox
    $toolboxDir = Get-ChildItem -Path $Path -Directory -Filter "*Repair Toolbox*" -ErrorAction SilentlyContinue | Select-Object -First 1
    $toolboxExe = $null
    if ($toolboxDir) {
        $toolboxExe = Get-ChildItem -Path $toolboxDir.FullName -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -match "Windows Repair Toolbox" } | Select-Object -First 1
    }
    if ($toolboxExe) {
        $WPF_TxtPWRTStatus.Text = "Détecté ($($toolboxExe.FullName))"
        $WPF_TxtPWRTStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
        $WPF_BtnRunPWRT.IsEnabled = $true
    } else {
        $WPF_TxtPWRTStatus.Text = "Non détecté"
        $WPF_TxtPWRTStatus.Foreground = [System.Windows.Media.Brushes]::Red
        $WPF_BtnRunPWRT.IsEnabled = $false
    }

    # Mettre à jour le chemin des drivers Optane par défaut si présent
    $optaneDir = Join-Path $Path "optane-script\Drivers"
    if (Test-Path $optaneDir) {
        $WPF_TxtOptaneDriverPath.Text = $optaneDir
    }
}

# --- Actions de la sélection de chemin (Overlay) ---

# Synchronisation entre la liste prédéfinie et le chemin personnalisé
$WPF_TxtCustomPath.Add_TextChanged({
    if (-not [string]::IsNullOrEmpty($WPF_TxtCustomPath.Text)) {
        $WPF_LstPredefinedPaths.UnselectAll()
    }
})

$WPF_LstPredefinedPaths.Add_SelectionChanged({
    if ($WPF_LstPredefinedPaths.SelectedItem) {
        $WPF_TxtCustomPath.Text = ""
    }
})

# Parcourir localement
$WPF_BtnBrowsePath.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Sélectionnez le dossier racine de la boîte à outils"
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $WPF_TxtCustomPath.Text = $dialog.SelectedPath
    }
})

# Valider la sélection
$WPF_BtnConfirmPath.Add_Click({
    $selectedPath = ""
    
    # 1. Priorité au chemin personnalisé s'il est rempli
    if (-not [string]::IsNullOrEmpty($WPF_TxtCustomPath.Text)) {
        $selectedPath = $WPF_TxtCustomPath.Text
    }
    # 2. Sinon, l'élément sélectionné dans la liste réseau
    elseif ($WPF_LstPredefinedPaths.SelectedItem) {
        $selectedPath = $WPF_LstPredefinedPaths.SelectedItem.ToString()
    }

    if (-not [string]::IsNullOrEmpty($selectedPath)) {
        if (-not (Test-Path $selectedPath -ErrorAction SilentlyContinue)) {
            [System.Windows.MessageBox]::Show("Le chemin spécifié est introuvable ou inaccessible. Si c'est un partage réseau, assurez-vous d'être connecté au réseau.", "Chemin invalide", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
            return
        }
        
        $Config.ToolsPath = $selectedPath
        
        # Sauvegarder dans la configuration si coché
        if ($WPF_SaveConfig.IsChecked) {
            $Config | ConvertTo-Json | Out-File $ConfigFile -Force
        }
    }

    # Mettre à jour et fermer l'overlay
    Update-ToolStatuses $Config.ToolsPath
    $WPF_PathSelectorOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $WPF_MainAppLayout.Visibility = [System.Windows.Visibility]::Visible
    
    # Lancer le diagnostic de base au démarrage
    Run-Diagnostics
})

# Ignorer (lancer l'outil sans outils tiers)
$WPF_BtnCancelPath.Add_Click({
    $Config.ToolsPath = ""
    Update-ToolStatuses ""
    $WPF_PathSelectorOverlay.Visibility = [System.Windows.Visibility]::Collapsed
    $WPF_MainAppLayout.Visibility = [System.Windows.Visibility]::Visible
    Run-Diagnostics
})

# Modifier le chemin depuis la Sidebar
$WPF_BtnChangePath.Add_Click({
    $WPF_MainAppLayout.Visibility = [System.Windows.Visibility]::Collapsed
    $WPF_PathSelectorOverlay.Visibility = [System.Windows.Visibility]::Visible
})

# --- Logique de navigation des onglets ---
$Grids = @($WPF_GridDiag, $WPF_GridClean, $WPF_GridRepair, $WPF_GridApps, $WPF_GridBackup, $WPF_GridOptane, $WPF_GridTools, $WPF_GridDownloads)

function Show-Tab ($activeGrid) {
    foreach ($grid in $Grids) {
        if ($grid -eq $activeGrid) {
            $grid.Visibility = [System.Windows.Visibility]::Visible
        } else {
            $grid.Visibility = [System.Windows.Visibility]::Collapsed
        }
    }
}

$WPF_BtnTabDiag.Add_Click({ Show-Tab $WPF_GridDiag })
$WPF_BtnTabClean.Add_Click({ Show-Tab $WPF_GridClean })
$WPF_BtnTabRepair.Add_Click({ Show-Tab $WPF_GridRepair })
$WPF_BtnTabApps.Add_Click({ 
    Show-Tab $WPF_GridApps 
    if ($WPF_LstInstalledApps.Items.Count -eq 0) {
        Populate-InstalledApps
    }
})
$WPF_BtnTabBackup.Add_Click({ Show-Tab $WPF_GridBackup })
$WPF_BtnTabOptane.Add_Click({ Show-Tab $WPF_GridOptane })
$WPF_BtnTabTools.Add_Click({ Show-Tab $WPF_GridTools })
$WPF_BtnTabDownloads.Add_Click({ 
    Show-Tab $WPF_GridDownloads
    Populate-Downloads
})

# --- LOGIQUE ONGLET : SCANNERS & DESINSTALLATION ---

$GlobalAppsLookup = @{}
$GlobalInstalledApps = @()
$GlobalCheckedApps = @{}

# Logger spécifique
function Log-App ($msg) {
    $WPF_TxtLogApps.Dispatcher.Invoke([Action[string]]{
        param($m) $WPF_TxtLogApps.AppendText("$m`r`n")
        $WPF_TxtLogApps.ScrollToEnd()
    }, $msg)
}

# Récupérer la liste des programmes installés via le registre
function Get-InstalledApps {
    $apps = @()
    $keys = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    foreach ($key in $keys) {
        if (Test-Path (Split-Path $key)) {
            $items = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName -and $item.SystemComponent -ne 1 -and $item.ParentKeyName -eq $null) {
                    # Éviter les doublons
                    if (-not ($apps | Where-Object { $_.Name -eq $item.DisplayName })) {
                        $apps += [PSCustomObject]@{
                            Name            = $item.DisplayName
                            Version         = $item.DisplayVersion
                            UninstallString = $item.UninstallString
                        }
                    }
                }
            }
        }
    }
    return $apps | Sort-Object Name
}

# Créer un élément CheckBox pour un programme
function New-AppCheckBox {
    param(
        [string]$appName
    )
    $chk = New-Object System.Windows.Controls.CheckBox
    $chk.Content = $appName
    $chk.Foreground = [System.Windows.Media.Brushes]::White
    $chk.Margin = "2"
    
    # Restaurer l'état coché si existant
    if ($GlobalCheckedApps.ContainsKey($appName)) {
        $chk.IsChecked = $GlobalCheckedApps[$appName]
    } else {
        $chk.IsChecked = $false
    }
    
    # Écouter les changements d'état avec capture de variable (closure)
    $chk.add_Checked({
        $GlobalCheckedApps[$appName] = $true
    }.GetNewClosure())
    $chk.add_Unchecked({
        $GlobalCheckedApps[$appName] = $false
    }.GetNewClosure())
    
    return $chk
}

# Remplir la liste WPF
function Populate-InstalledApps {
    $WPF_TxtLogApps.Text = "Chargement de la liste des programmes installés...`r`n"
    $WPF_LstInstalledApps.Items.Clear()
    $GlobalAppsLookup.Clear()
    $GlobalCheckedApps.Clear() # Vider les sélections précédentes lors d'un rafraîchissement complet
    
    $global:GlobalInstalledApps = Get-InstalledApps
    foreach ($app in $GlobalInstalledApps) {
        $GlobalAppsLookup[$app.Name] = $app.UninstallString
        $chk = New-AppCheckBox -appName $app.Name
        [void]$WPF_LstInstalledApps.Items.Add($chk)
    }
    Log-App "[OK] $($GlobalInstalledApps.Count) programmes chargés."
}

# Lancer la désinstallation séquentielle des programmes cochés
$WPF_BtnUninstallApp.Add_Click({
    $selectedApps = @()
    foreach ($key in $GlobalCheckedApps.Keys) {
        if ($GlobalCheckedApps[$key]) {
            $selectedApps += $key
        }
    }

    if ($selectedApps.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Veuillez cocher au moins un programme à désinstaller.", "Sélection vide", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    # Créer la liste des commandes à exécuter
    $jobsList = @()
    foreach ($name in $selectedApps) {
        $cmd = $GlobalAppsLookup[$name]
        if ($cmd) {
            $jobsList += [PSCustomObject]@{
                Name = $name
                Cmd  = $cmd
            }
        }
    }

    Log-App "[>>] Début de la désinstallation en lot de $($jobsList.Count) programmes..."
    
    Start-ThreadJob -ArgumentList @(, $jobsList) {
        param($items)
        foreach ($item in $items) {
            Write-Output "[>>] Désinstallation de : $($item.Name)"
            Write-Output "Lancement de la commande : $($item.Cmd)"
            try {
                # Exécuter via cmd.exe en tant qu'admin et attendre la fermeture
                $process = Start-Process cmd.exe -ArgumentList "/c `"$($item.Cmd)`"" -Verb RunAs -Wait -PassThru
                Write-Output "[OK] Désinstallation de $($item.Name) terminée (Code de sortie : $($process.ExitCode))."
            } catch {
                Write-Output "[!!] Erreur lors du lancement pour $($item.Name) : $($_.Exception.Message)"
            }
        }
        return "[FIN] Toutes les désinstallations sélectionnées sont terminées."
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-App $_
    }
    
    # Rafraîchir après la fin de toutes les désinstallations
    Populate-InstalledApps
})

# Filtrer la liste en temps réel (tout en préservant l'état des cases cochées)
$WPF_TxtSearchApps.Add_TextChanged({
    $search = $WPF_TxtSearchApps.Text.Trim()
    $WPF_LstInstalledApps.Items.Clear()
    foreach ($app in $GlobalInstalledApps) {
        if ([string]::IsNullOrEmpty($search) -or $app.Name -like "*$search*") {
            $chk = New-AppCheckBox -appName $app.Name
            [void]$WPF_LstInstalledApps.Items.Add($chk)
        }
    }
})

# Rafraîchir la liste
$WPF_BtnRefreshApps.Add_Click({
    Populate-InstalledApps
})

# Fonction pour gérer les scanners jetables
function Start-DisposableScanner {
    param([string]$Name, [string]$Url)
    
    Log-App "[>>] Démarrage du processus pour $Name..."
    
    Start-ThreadJob -ArgumentList $Name, $Url {
        param($n, $u)
        
        $tempDir = Join-Path $env:TEMP "JDS-Scanners"
        if (-not (Test-Path $tempDir)) { 
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null 
        }
        
        $filePath = Join-Path $tempDir "$n.exe"
        
        # 1. Téléchargement via curl.exe (contourne tous les bugs SSL de .NET)
        Write-Output "[>>] Téléchargement de la dernière version de $n via curl..."
        try {
            $curlArgs = "-L -k -s -o `"$filePath`" -A `"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`" `"$u`""
            $process = Start-Process curl.exe -ArgumentList $curlArgs -Wait -NoNewWindow -PassThru
            
            if ($process.ExitCode -ne 0 -or -not (Test-Path $filePath) -or (Get-Item $filePath).Length -lt 10KB) {
                $err = "Code sortie curl: $($process.ExitCode)"
                if (Test-Path $filePath) {
                    $err += " (Taille du fichier: $((Get-Item $filePath).Length) octets)"
                    Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
                }
                return "[!!] Échec du téléchargement de $n : $err"
            }
        } catch {
            return "[!!] Échec du lancement de curl.exe : $($_.Exception.Message)"
        }
        
        # 2. Exécution
        Write-Output "[>>] Lancement de $n (en tant qu'admin)..."
        try {
            $process = Start-Process -FilePath $filePath -Wait -PassThru -Verb RunAs
            Write-Output "[>>] $n est en cours d'exécution. En attente de la fermeture..."
            $process.WaitForExit()
            $code = $process.ExitCode
        } catch {
            # Nettoyer quand même si le lancement a échoué après création
            if (Test-Path $filePath) { Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue }
            return "[!!] Échec du lancement de $n : $($_.Exception.Message)"
        }
        
        # 3. Suppression automatique (ne s'applique pas si Malwarebytes Installer)
        if ($n -ne "MalwarebytesInstaller") {
            Write-Output "[>>] Suppression du fichier temporaire de $n..."
            if (Test-Path $filePath) {
                # Petite pause pour libérer le descripteur de fichier si nécessaire
                Start-Sleep -Seconds 2
                Remove-Item -Path $filePath -Force -ErrorAction SilentlyContinue
            }
            return "[OK] $n a été fermé et désinstallé (supprimé) avec succès. (Code de sortie : $code)"
        } else {
            return "[OK] Malwarebytes installé. Utilisez le Désinstalleur Express de l'application pour le retirer plus tard si nécessaire. (Code de sortie : $code)"
        }
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-App $_
    }
}

# KVRT
$WPF_BtnRunKVRT.Add_Click({
    Start-DisposableScanner -Name "KasperskyVirusRemovalTool" -Url "https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe"
})

# AdwCleaner
$WPF_BtnRunAdw.Add_Click({
    Start-DisposableScanner -Name "AdwCleaner" -Url "https://downloads.malwarebytes.com/file/adwcleaner"
})

# ESET Online Scanner
$WPF_BtnRunEset.Add_Click({
    Start-DisposableScanner -Name "ESETOnlineScanner" -Url "https://download.eset.com/com/eset/tools/online_scanner/latest/esetonlinescanner_fra.exe"
})

# RogueKiller (Portable)
$WPF_BtnRunRogue.Add_Click({
    Start-DisposableScanner -Name "RogueKiller" -Url "https://download.adlice.com/api/?action=download&app=roguekiller&type=portable64"
})

# Malwarebytes (Installer)
$WPF_BtnRunMBAM.Add_Click({
    Start-DisposableScanner -Name "MalwarebytesInstaller" -Url "https://downloads.malwarebytes.com/file/mb4_offline"
})


# --- LOGIQUE ONGLET : TELECHARGEMENTS PERSISTANTS ---

$GlobalToolsList = @()

# Extraire la version locale de l'exécutable
function Get-LocalToolVersion ($filePath) {
    if (Test-Path $filePath) {
        try {
            $info = (Get-Item $filePath).VersionInfo
            if ($info.ProductVersion) {
                return $info.ProductVersion.Trim()
            } elseif ($info.FileVersion) {
                return $info.FileVersion.Trim()
            } else {
                return "Présent"
            }
        } catch {
            return "Présent"
        }
    }
    return "Absent"
}

# Enregistrer des logs de téléchargement détaillés dans un fichier physique
function Log-Download ($msg) {
    if (-not [string]::IsNullOrEmpty($Config.ToolsPath)) {
        try {
            $logPath = Join-Path $Config.ToolsPath "JDS-Downloads.log"
            $timestamp = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss")
            "[ $timestamp ] $msg" | Out-File -FilePath $logPath -Append -Encoding utf8
        } catch {}
    }
}

# Ouvrir le fichier de log de téléchargement dans Notepad
$WPF_BtnOpenDownloadLog.Add_Click({
    if (-not [string]::IsNullOrEmpty($Config.ToolsPath)) {
        $logPath = Join-Path $Config.ToolsPath "JDS-Downloads.log"
        if (Test-Path $logPath) {
            Start-Process notepad.exe $logPath
        } else {
            [System.Windows.MessageBox]::Show("Aucune entrée de log n'a encore été créée.", "Log vide", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    } else {
        [System.Windows.MessageBox]::Show("Veuillez d'abord sélectionner un dossier de boîte à outils.", "Dossier non sélectionné", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
    }
})

# Charger le catalogue et remplir la liste des téléchargements
function Populate-Downloads {
    if ([string]::IsNullOrEmpty($Config.ToolsPath)) {
        $WPF_LstDownloads.Items.Clear()
        $lbl = New-Object System.Windows.Controls.Label
        $lbl.Content = "Veuillez sélectionner un dossier racine valide pour les outils dans la sidebar."
        $lbl.Foreground = [System.Windows.Media.Brushes]::Red
        $lbl.HorizontalAlignment = [System.Windows.HorizontalAlignment]::Center
        $lbl.Margin = 20
        [void]$WPF_LstDownloads.Items.Add($lbl)
        return
    }

    $WPF_TxtProgressStatus.Text = "Chargement du catalogue des versions..."
    $WPF_LstDownloads.Items.Clear()

    # Déclarer l'instance de BrushConverter pour la gestion des couleurs WPF
    $BrushConverter = New-Object System.Windows.Media.BrushConverter

    # Charger versions.json depuis GitHub en temps réel (via curl.exe pour éviter les blocages SSL .NET)
    try {
        $catalogUrl = "https://raw.githubusercontent.com/john2k/JDS-Repair-Toolkit/main/versions.json?t=" + [DateTime]::Now.Ticks
        $curlOutput = & curl.exe -L -k -s $catalogUrl
        $jsonContent = $curlOutput -join "`n"
        if ([string]::IsNullOrEmpty($jsonContent) -or -not ($jsonContent.Trim().StartsWith("["))) {
            throw "Réponse JSON invalide ou vide"
        }
        $global:GlobalToolsList = $jsonContent | ConvertFrom-Json
        Log-Download "[OK] Catalogue de téléchargement chargé. $($global:GlobalToolsList.Count) outils référencés."
    } catch {
        $WPF_TxtProgressStatus.Text = "Échec du chargement du catalogue via curl : $($_.Exception.Message)"
        Log-Download "[!!] Échec du chargement du catalogue versions.json en ligne : $($_.Exception.Message)"
        return
    }

    $WPF_TxtProgressStatus.Text = "Analyse des fichiers locaux et comparaison..."

    foreach ($tool in $global:GlobalToolsList) {
        $dirPath = Join-Path $Config.ToolsPath "Logiciels\$($tool.folder)"
        $filename = $tool.filename
        $localFile = Join-Path $dirPath $filename
        $localVer = Get-LocalToolVersion -filePath $localFile
        
        $statusText = ""
        $colorBrush = $null
        $btnText = ""
        $btnEnabled = $true

        if ($localVer -eq "Absent") {
            $statusText = "Non installé"
            $colorBrush = [System.Windows.Media.Brushes]::Red
            $btnText = "Télécharger"
        } else {
            if ($localVer -eq $tool.version) {
                $statusText = "À jour"
                $colorBrush = [System.Windows.Media.Brushes]::LightGreen
                $btnText = "Réinstaller"
            } else {
                $statusText = "Mise à jour disponible"
                $colorBrush = [System.Windows.Media.Brushes]::Orange
                $btnText = "Mettre à jour"
            }
        }

        # Créer le template WPF programmatiquement
        $itemGrid = New-Object System.Windows.Controls.Grid
        $itemGrid.Margin = "5"
        
        $col0 = New-Object System.Windows.Controls.ColumnDefinition; $col0.Width = New-Object System.Windows.GridLength(320); $itemGrid.ColumnDefinitions.Add($col0)
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = New-Object System.Windows.GridLength(180); $itemGrid.ColumnDefinitions.Add($col1)
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(150); $itemGrid.ColumnDefinitions.Add($col2)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto; $itemGrid.ColumnDefinitions.Add($col3)

        # Name block
        $spName = New-Object System.Windows.Controls.StackPanel
        $txtName = New-Object System.Windows.Controls.TextBlock; $txtName.Text = $tool.name; $txtName.FontWeight = [System.Windows.FontWeights]::Bold; $txtName.Foreground = [System.Windows.Media.Brushes]::White; $txtName.FontSize = 13
        $txtCat = New-Object System.Windows.Controls.TextBlock; $txtCat.Text = $tool.category; $txtCat.Foreground = [System.Windows.Media.Brushes]::Gray; $txtCat.FontSize = 10; $txtCat.Margin = "0,2,0,0"
        $spName.Children.Add($txtName) | Out-Null
        $spName.Children.Add($txtCat) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($spName, 0)
        $itemGrid.Children.Add($spName) | Out-Null

        # Version block
        $spVer = New-Object System.Windows.Controls.StackPanel
        $txtLocalVer = New-Object System.Windows.Controls.TextBlock; $txtLocalVer.Text = "Local : $localVer"; $txtLocalVer.Foreground = [System.Windows.Media.Brushes]::LightGray; $txtLocalVer.FontSize = 11
        $txtRemoteVer = New-Object System.Windows.Controls.TextBlock; $txtRemoteVer.Text = "Distant : $($tool.version)"; $txtRemoteVer.Foreground = [System.Windows.Media.Brushes]::Gray; $txtRemoteVer.FontSize = 11; $txtRemoteVer.Margin = "0,2,0,0"
        $spVer.Children.Add($txtLocalVer) | Out-Null
        $spVer.Children.Add($txtRemoteVer) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($spVer, 1)
        $itemGrid.Children.Add($spVer) | Out-Null

        # Status block
        $spStatus = New-Object System.Windows.Controls.StackPanel
        $spStatus.Orientation = [System.Windows.Controls.Orientation]::Horizontal
        $spStatus.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
        
        $pastille = New-Object System.Windows.Controls.Border
        $pastille.Width = 10; $pastille.Height = 10; $pastille.CornerRadius = New-Object System.Windows.CornerRadius(5)
        $pastille.Background = $colorBrush; $pastille.Margin = "0,0,8,0"
        
        $txtStatus = New-Object System.Windows.Controls.TextBlock
        $txtStatus.Text = $statusText; $txtStatus.Foreground = $colorBrush; $txtStatus.FontSize = 11; $txtStatus.FontWeight = [System.Windows.FontWeights]::SemiBold
        
        $spStatus.Children.Add($pastille) | Out-Null
        $spStatus.Children.Add($txtStatus) | Out-Null
        [System.Windows.Controls.Grid]::SetColumn($spStatus, 2)
        $itemGrid.Children.Add($spStatus) | Out-Null

        # Action Button
        $btnAction = New-Object System.Windows.Controls.Button
        $btnAction.Content = $btnText
        $btnAction.Width = 110; $btnAction.Height = 24; $btnAction.IsEnabled = $btnEnabled
        $btnAction.FontWeight = [System.Windows.FontWeights]::Bold; $btnAction.FontSize = 11; $btnAction.Cursor = [System.Windows.Input.Cursors]::Hand
        
        if ($statusText -eq "À jour") {
            $btnAction.Background = $BrushConverter.ConvertFromString("#2D3748")
            $btnAction.Foreground = [System.Windows.Media.Brushes]::LightGray
        } else {
            $btnAction.Background = $BrushConverter.ConvertFromString("#00adb5")
            $btnAction.Foreground = [System.Windows.Media.Brushes]::White
        }

        # Liaison événement Clic avec fermeture
        $toolId = $tool.id
        $btnAction.Add_Click({
            Download-PersistentTool -ToolId $toolId
        }.GetNewClosure())

        [System.Windows.Controls.Grid]::SetColumn($btnAction, 3)
        $itemGrid.Children.Add($btnAction) | Out-Null

        # Border wrapper
        $itemBorder = New-Object System.Windows.Controls.Border
        $itemBorder.Background = $BrushConverter.ConvertFromString("#252530")
        $itemBorder.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $itemBorder.Padding = New-Object System.Windows.Thickness(8)
        $itemBorder.Margin = New-Object System.Windows.Thickness(0,0,0,6)
        $itemBorder.Child = $itemGrid
        [void]$WPF_LstDownloads.Items.Add($itemBorder)
    }

    $WPF_TxtProgressStatus.Text = "Prêt (Tous les statuts de version chargés)."
}

# Lancer le téléchargement asynchrone non-bloquant de l'outil via curl.exe avec suivi de taille et écriture de log
function Download-PersistentTool {
    param(
        [string]$ToolId
    )

    $tool = $global:GlobalToolsList | Where-Object { $_.id -eq $ToolId }
    if (-not $tool) { return }

    Log-Download "[>>] Démarrage de la procédure de téléchargement de : $($tool.name)"

    # Préparer les répertoires de stockage (Logiciels\NomOutil)
    $dirPath = Join-Path $Config.ToolsPath "Logiciels\$($tool.folder)"
    if (-not (Test-Path $dirPath)) {
        New-Item -ItemType Directory -Path $dirPath -Force | Out-Null
        Log-Download "Création du dossier de stockage : $dirPath"
    }

    # Déterminer si zip ou exe
    $url = $tool.url
    $extension = ".exe"
    if ($url -match "\.zip") {
        $extension = ".zip"
    }
    
    $tempFileName = "$($tool.id)$extension"
    $tempFilePath = Join-Path $dirPath $tempFileName
    Log-Download "URL cible : $url"
    Log-Download "Fichier local final : $tempFilePath"

    # Supprimer l'existant s'il y a lieu pour recommencer proprement
    if (Test-Path $tempFilePath) { 
        Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue 
        Log-Download "Nettoyage du fichier temporaire préexistant."
    }

    $WPF_TxtProgressStatus.Text = "Lancement du téléchargement de $($tool.name)..."
    $WPF_TxtProgressSpeed.Text = "Connexion..."
    $WPF_ProgressDownload.Value = 0
    $WPF_ProgressDownload.IsIndeterminate = $true

    $global:DownloadStartTime = [DateTime]::Now

    # Lancer le téléchargement via curl.exe directement (sans Start-Process) pour un traitement parfait des arguments et des espaces
    $job = Start-ThreadJob -ArgumentList $tempFilePath, $url {
        param($path, $downloadUrl)
        & curl.exe -L -k -s -o $path -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" $downloadUrl
        return $LASTEXITCODE
    }
    Log-Download "Thread Job lancé en tâche de fond. Surveillance démarrée."

    # Démarrer un Timer WPF pour surveiller la taille du fichier et calculer la vitesse
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(500)
    
    $timer.Add_Tick(({
        # Sécurité : Si le timer est orphelin/stale (ex: après fermeture/relance du script), auto-destruction
        if ([string]::IsNullOrEmpty($tempFilePath) -or $null -eq $timer) {
            try { $timer.Stop() } catch {}
            return
        }

        # Si le job asynchrone est terminé
        if ($null -eq $job -or $job.AsyncResult.IsCompleted) {
            $timer.Stop()
            $WPF_ProgressDownload.IsIndeterminate = $false
            
            # Récupérer le code de retour du job
            $exitCode = Receive-Job -Job $job
            Log-Download "Thread de téléchargement terminé. Code retour curl: $exitCode."
            
            if ($exitCode -ne 0 -or -not (Test-Path $tempFilePath) -or (Get-Item $tempFilePath).Length -lt 10KB) {
                $fileLength = 0
                if (Test-Path $tempFilePath) {
                    $fileLength = (Get-Item $tempFilePath).Length
                }
                $WPF_TxtProgressStatus.Text = "Échec du téléchargement de $($tool.name) (Code curl: $exitCode)."
                $WPF_TxtProgressSpeed.Text = ""
                $WPF_ProgressDownload.Value = 0
                Log-Download "[!!] ÉCHEC du téléchargement de $($tool.name). Code curl: $exitCode. Taille du fichier écrit: $fileLength octets."
                if (Test-Path $tempFilePath) { Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue }
            } else {
                # Succès !
                Log-Download "[OK] Fichier téléchargé avec succès. Poids final : $((Get-Item $tempFilePath).Length) octets."
                if ($tempFilePath.EndsWith(".zip")) {
                    $WPF_TxtProgressStatus.Text = "Extraction de l'archive ZIP de $($tool.name)..."
                    $WPF_TxtProgressSpeed.Text = ""
                    Log-Download "Extraction de l'archive ZIP lancée vers : $dirPath"
                    try {
                        Expand-Archive -Path $tempFilePath -DestinationPath $dirPath -Force
                        Remove-Item -Path $tempFilePath -Force -ErrorAction SilentlyContinue
                        $WPF_TxtProgressStatus.Text = "Téléchargement et extraction de $($tool.name) terminés !"
                        Log-Download "[OK] Décompression ZIP terminée avec succès. Nettoyage de l'archive effectué."
                    } catch {
                        $WPF_TxtProgressStatus.Text = "Erreur d'extraction ZIP : $($_.Exception.Message)"
                        Log-Download "[!!] Erreur d'extraction du ZIP : $($_.Exception.Message)"
                    }
                } else {
                    $WPF_TxtProgressStatus.Text = "Téléchargement de $($tool.name) terminé !"
                    $WPF_TxtProgressSpeed.Text = ""
                }
                $WPF_ProgressDownload.Value = 100
                Populate-Downloads
            }
            return
        }

        # Mettre à jour l'affichage de la progression
        if (Test-Path $tempFilePath) {
            try {
                $file = Get-Item $tempFilePath
                $currentSize = $file.Length
                $sizeMB = ($currentSize / 1MB).ToString("F1")
                
                # Calcul de la vitesse moyenne de téléchargement
                $elapsed = ([DateTime]::Now - $global:DownloadStartTime).TotalSeconds
                if ($elapsed -gt 0.1) {
                    $speedVal = ($currentSize / $elapsed) / 1MB
                    $WPF_TxtProgressSpeed.Text = "$($speedVal.ToString('F2')) MB/s"
                }
                
                $WPF_TxtProgressStatus.Text = "Téléchargement de $($tool.name) : $sizeMB MB transférés"
            } catch {}
        }
    }).GetNewClosure())

    $timer.Start()
}

# Événements bouton rafraîchir
$WPF_BtnRefreshDownloads.Add_Click({
    Populate-Downloads
})


# --- ONGLET 1 : DIAGNOSTICS ---
function Run-Diagnostics {
    $WPF_TxtDiagOS.Text = "Analyse de l'OS..."
    $WPF_TxtDiagCPU.Text = "Analyse du CPU..."
    $WPF_TxtDiagRAM.Text = "Analyse de la RAM..."
    $WPF_TxtDiagMB.Text = "Analyse de la Carte Mère..."
    $WPF_TxtDiagAV.Text = "Recherche des logiciels de sécurité..."
    $WPF_TxtDiagDisks.Text = "Analyse SMART des disques..."

    # Lancer en arrière-plan pour ne pas geler l'UI
    Start-ThreadJob {
        # OS Info
        $os = Get-CimInstance Win32_OperatingSystem
        $osText = "OS : $($os.Caption) ($($os.OSArchitecture)) - Build $($os.Version)"
        
        # CPU
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $cpuText = "Processeur : $($cpu.Name.Trim())"

        # RAM
        $ramBytes = (Get-CimInstance Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
        $ramText = "Mémoire RAM : " + [math]::Round($ramBytes / 1GB, 1) + " Go installés"

        # Board
        $board = Get-CimInstance Win32_BaseBoard
        $mbText = "Carte Mère : $($board.Manufacturer) $($board.Product)"

        # Antivirus
        $avList = @()
        try {
            $wmiAV = Get-CimInstance -Namespace "root\SecurityCenter2" -ClassName "AntiVirusProduct" -ErrorAction SilentlyContinue
            if ($wmiAV) {
                foreach ($av in $wmiAV) {
                    $avList += $av.displayName
                }
            }
        } catch {}
        if ($avList.Count -eq 0) { $avList += "Aucun antivirus tiers détecté (Windows Defender uniquement ou non référencé)" }
        $avText = "Antivirus : " + ($avList -join ", ")

        # Disques SMART
        $diskInfo = ""
        try {
            $disks = Get-PhysicalDisk
            foreach ($d in $disks) {
                $status = $d.HealthStatus
                $diskInfo += "Disque #$($d.DeviceId) - $($d.FriendlyName) ($([math]::Round($d.Size / 1GB, 0)) Go) - Santé: $status`r`n"
            }
        } catch {
            $diskInfo = "Erreur lors de la récupération des informations de disque physique."
        }

        # Renvoyer les résultats à l'UI
        return @{
            os = $osText
            cpu = $cpuText
            ram = $ramText
            mb = $mbText
            av = $avText
            disks = $diskInfo
        }
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        $WPF_TxtDiagOS.Text = $_.os
        $WPF_TxtDiagCPU.Text = $_.cpu
        $WPF_TxtDiagRAM.Text = $_.ram
        $WPF_TxtDiagMB.Text = $_.mb
        $WPF_TxtDiagAV.Text = $_.av
        $WPF_TxtDiagDisks.Text = $_.disks
    }
}
$WPF_BtnRefreshDiag.Add_Click({ Run-Diagnostics })


# --- ONGLET 2 : NETTOYAGE ---
$WPF_BtnOpenAppwiz.Add_Click({
    Start-Process appwiz.cpl
})

$WPF_BtnStartClean.Add_Click({
    $WPF_TxtLogClean.Text = "Début du nettoyage...`r`n"
    
    $cleanTemp = $WPF_ChkCleanTemp.IsChecked
    $cleanWU = $WPF_ChkCleanUpdate.IsChecked
    $cleanBrowsers = $WPF_ChkCleanBrowsers.IsChecked

    # Exécution dans un thread
    Start-ThreadJob -ArgumentList $cleanTemp, $cleanWU, $cleanBrowsers {
        param($temp, $wu, $browsers)
        $log = ""

        if ($temp) {
            $log += "[>>] Nettoyage des fichiers temporaires Windows...`r`n"
            $tempPaths = @("$env:SystemRoot\Temp", "$env:LOCALAPPDATA\Temp")
            foreach ($path in $tempPaths) {
                if (Test-Path $path) {
                    Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            $log += "[OK] Fichiers temporaires nettoyés.`r`n"
        }

        if ($wu) {
            $log += "[>>] Arrêt des services liés aux mises à jour...`r`n"
            Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
            Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
            
            $log += "[>>] Suppression du cache Windows Update...`r`n"
            $wuPath = "$env:SystemRoot\SoftwareDistribution"
            if (Test-Path $wuPath) {
                Get-ChildItem -Path $wuPath -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
            }

            $log += "[>>] Redémarrage des services...`r`n"
            Start-Service -Name wuauserv -ErrorAction SilentlyContinue
            Start-Service -Name bits -ErrorAction SilentlyContinue
            $log += "[OK] Cache Windows Update réinitialisé.`r`n"
        }

        if ($browsers) {
            $log += "[>>] Nettoyage des caches de navigateurs (Chrome, Edge, Firefox)...`r`n"
            $local = $env:LOCALAPPDATA
            $roaming = $env:APPDATA
            $browserPaths = @(
                "$local\Google\Chrome\User Data\Default\Cache",
                "$local\Microsoft\Edge\User Data\Default\Cache",
                "$roaming\Mozilla\Firefox\Profiles"
            )
            foreach ($bp in $browserPaths) {
                if (Test-Path $bp) {
                    if ($bp -like "*Firefox*") {
                        # Supprimer cache dans chaque profil Firefox
                        Get-ChildItem -Path $bp -Directory | ForEach-Object {
                            $cacheDir = Join-Path $_.FullName "cache2"
                            if (Test-Path $cacheDir) { Remove-Item -Path $cacheDir -Recurse -Force -ErrorAction SilentlyContinue }
                        }
                    } else {
                        Get-ChildItem -Path $bp -Recurse -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            $log += "[OK] Caches des navigateurs purgés.`r`n"
        }

        $log += "[FIN] Opération de nettoyage terminée !`r`n"
        return $log
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        $WPF_TxtLogClean.Text = $_
    }
})


# --- ONGLET 3 : REPARATIONS ---
function Log-Repair ($msg) {
    $WPF_TxtLogRepair.Dispatcher.Invoke([Action[string]]{
        param($m) $WPF_TxtLogRepair.AppendText("$m`r`n")
        $WPF_TxtLogRepair.ScrollToEnd()
    }, $msg)
}

# SFC
$WPF_BtnRunSFC.Add_Click({
    $WPF_TxtLogRepair.Text = "Lancement de SFC /scannow (ceci peut prendre plusieurs minutes)...`r`n"
    Start-ThreadJob {
        $process = Start-Process sfc.exe -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-Repair "[OK] SFC terminé avec le code : $_"
    }
})

# DISM
$WPF_BtnRunDISM.Add_Click({
    $WPF_TxtLogRepair.Text = "Lancement de DISM RestoreHealth (connexion Internet requise)...`r`n"
    Start-ThreadJob {
        $process = Start-Process dism.exe -ArgumentList "/Online /Cleanup-Image /RestoreHealth" -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-Repair "[OK] DISM terminé avec le code : $_"
    }
})

# Windows Update Service Full Reset
$WPF_BtnFixWU.Add_Click({
    $WPF_TxtLogRepair.Text = "Lancement de la réinitialisation de Windows Update...`r`n"
    Start-ThreadJob {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Stop-Service -Name bits -Force -ErrorAction SilentlyContinue
        Stop-Service -Name cryptsvc -Force -ErrorAction SilentlyContinue
        Stop-Service -Name msiserver -Force -ErrorAction SilentlyContinue
        
        # Renommer les dossiers importants
        $winDir = $env:SystemRoot
        if (Test-Path "$winDir\SoftwareDistribution") {
            Remove-Item -Path "$winDir\SoftwareDistribution.old" -Recurse -Force -ErrorAction SilentlyContinue
            Rename-Item -Path "$winDir\SoftwareDistribution" -NewName "SoftwareDistribution.old" -ErrorAction SilentlyContinue
        }
        if (Test-Path "$winDir\System32\catroot2") {
            Remove-Item -Path "$winDir\System32\catroot2.old" -Recurse -Force -ErrorAction SilentlyContinue
            Rename-Item -Path "$winDir\System32\catroot2" -NewName "catroot2.old" -ErrorAction SilentlyContinue
        }

        # Réinitialiser les descripteurs de sécurité de service
        sc.exe sdset wuauserv "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" | Out-Null
        sc.exe sdset bits "D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;AU)(A;;CCLCSWRPWPDTLOCRRC;;;PU)" | Out-Null

        # Redémarrer les services
        Start-Service -Name wuauserv -ErrorAction SilentlyContinue
        Start-Service -Name bits -ErrorAction SilentlyContinue
        Start-Service -Name cryptsvc -ErrorAction SilentlyContinue
        Start-Service -Name msiserver -ErrorAction SilentlyContinue
        return "Windows Update réinitialisé avec succès (Dossiers SoftwareDistribution/catroot2 renommés en .old)."
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-Repair "[OK] $_"
    }
})

# Network Reset
$WPF_BtnResetNetwork.Add_Click({
    $WPF_TxtLogRepair.Text = "Réinitialisation des protocoles réseau en cours...`r`n"
    Start-ThreadJob {
        $log = ""
        $log += "Flush DNS... " + (ipconfig /flushdns) + "`r`n"
        $log += "Winsock Reset... " + (netsh winsock reset) + "`r`n"
        $log += "IP Reset... " + (netsh int ip reset) + "`r`n"
        return $log
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-Repair $_
        Log-Repair "[OK] Réinitialisation réseau effectuée. Un redémarrage peut être nécessaire."
    }
})

# Audit Tasks
$WPF_BtnAuditTasks.Add_Click({
    $WPF_TxtLogRepair.Text = "Audit des tâches planifiées non Microsoft / suspectes...`r`n"
    Start-ThreadJob {
        # Rechercher les tâches qui ne proviennent pas de Microsoft
        $tasks = Get-ScheduledTask | Where-Object { $_.TaskPath -notlike "\Microsoft*" }
        $result = ""
        foreach ($t in $tasks) {
            $result += "Nom : $($t.TaskName) | Chemin : $($t.TaskPath) | Statut : $($t.State)`r`n"
        }
        if ([string]::IsNullOrEmpty($result)) { $result = "Aucune tâche suspecte / tierce trouvée." }
        return $result
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        Log-Repair $_
    }
})


# --- ONGLET 4 : SAUVEGARDE ---
# Lancer Fab's AutoBackup
$WPF_BtnRunFAB.Add_Click({
    $fabExe = Join-Path $Config.ToolsPath "FAB\AutoBackup7Pro.exe"
    if (Test-Path $fabExe) {
        Start-Process $fabExe
    }
})

# Sauvegarde Native alternative
$WPF_BtnRunNativeBackup.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Sélectionnez le dossier de destination pour la sauvegarde rapide"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $dest = $dialog.SelectedPath
        $userProfile = $env:USERPROFILE
        
        # Dossiers sources
        $folders = @("Documents", "Desktop", "Favorites", "Pictures", "Downloads")
        
        Start-ThreadJob -ArgumentList $dest, $userProfile, $folders {
            param($d, $up, $f)
            $log = ""
            foreach ($folder in $f) {
                $src = Join-Path $up $folder
                $target = Join-Path $d $folder
                if (Test-Path $src) {
                    $log += "Copie de $folder vers la destination...`r`n"
                    Copy-Item -Path $src -Destination $target -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            return $log
        } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
            [System.Windows.MessageBox]::Show("Sauvegarde native terminée :`r`n$_", "Sauvegarde Native", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Information)
        }
    }
})


# --- ONGLET 5 : DRIVERS & OPTANE ---
# Parcourir les drivers
$WPF_BtnBrowseOptaneDrivers.Add_Click({
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Sélectionnez le dossier contenant les fichiers .inf des pilotes Intel RST/Optane"
    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $WPF_TxtOptaneDriverPath.Text = $dialog.SelectedPath
    }
})

# Injection DISM
$WPF_BtnRunOptaneInjection.Add_Click({
    $windowsLetter = $WPF_TxtOptaneDrive.Text.Trim().TrimEnd(':').ToUpper()
    $driverPath = $WPF_TxtOptaneDriverPath.Text.Trim()

    if ($windowsLetter -notmatch '^[A-Z]$') {
        [System.Windows.MessageBox]::Show("La lettre de lecteur doit être une seule lettre de A à Z.", "Entrée invalide", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Error)
        return
    }

    $imagePath = "${windowsLetter}:\"
    $system32Path = "${imagePath}Windows\System32"

    if (-not (Test-Path $system32Path)) {
        [System.Windows.MessageBox]::Show("Le dossier '$system32Path' est introuvable. Assurez-vous que cette lettre correspond bien à la partition Windows à modifier.", "Partition Windows introuvable", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    if (-not (Test-Path $driverPath)) {
        [System.Windows.MessageBox]::Show("Le dossier des pilotes spécifié est introuvable.", "Pilotes introuvables", [System.Windows.MessageBoxButton]::OK, [System.Windows.MessageBoxImage]::Warning)
        return
    }

    $WPF_TxtLogOptane.Text = "[>>] Préparation de l'injection des pilotes...`r`n"
    $WPF_TxtLogOptane.AppendText("Cible : $imagePath`r`n")
    $WPF_TxtLogOptane.AppendText("Pilotes : $driverPath`r`n`r`n")

    Start-ThreadJob -ArgumentList $imagePath, $driverPath {
        param($img, $drvs)
        $process = Start-Process dism.exe -ArgumentList "/Image:$img /Add-Driver /Driver:`"$drvs`" /Recurse" -NoNewWindow -Wait -PassThru
        return $process.ExitCode
    } | Receive-Job -Wait -AutoRemoveJob | ForEach-Object {
        if ($_ -eq 0) {
            $WPF_TxtLogOptane.AppendText("[OK] Injection terminée avec succès (Code 0).`r`n")
        } else {
            $WPF_TxtLogOptane.AppendText("[!!] Erreur lors de l'injection DISM (Code: $_).`r`n")
        }
    }
})


# --- ONGLET 6 : OUTILS TIERS ---
# Tron Script
$WPF_BtnRunTron.Add_Click({
    $tronDir = Get-ChildItem -Path $Config.ToolsPath -Directory -Filter "Tron*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($tronDir) {
        $tronBat = Join-Path $tronDir.FullName "tron\tron.bat"
        if (Test-Path $tronBat) {
            # Lancer dans une nouvelle fenêtre cmd en tant qu'admin
            Start-Process cmd.exe -ArgumentList "/c `"$tronBat`"" -Verb RunAs
        }
    }
})

# Windows Repair Unlocked (Tweaking)
$WPF_BtnRunTweaking.Add_Click({
    $repairDir = Get-ChildItem -Path $Config.ToolsPath -Directory -Filter "*Repair*" -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Name -match "Windows Repair Unlocked" } | Select-Object -First 1
    if ($repairDir) {
        $repairExe = Get-ChildItem -Path $repairDir.FullName -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -match "Windows Repair" -or $_.Name -match "Repair_Windows" } | Select-Object -First 1
        if ($repairExe) {
            Start-Process $repairExe.FullName -Verb RunAs
        }
    }
})

# Portable Windows Repair Toolbox
$WPF_BtnRunPWRT.Add_Click({
    $toolboxDir = Get-ChildItem -Path $Config.ToolsPath -Directory -Filter "*Repair Toolbox*" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($toolboxDir) {
        $toolboxExe = Get-ChildItem -Path $toolboxDir.FullName -Filter "*.exe" -Recurse -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Name -match "Windows Repair Toolbox" } | Select-Object -First 1
        if ($toolboxExe) {
            Start-Process $toolboxExe.FullName -Verb RunAs
        }
    }
})

# Ouvrir services.msc
$WPF_BtnOpenServices.Add_Click({
    Start-Process services.msc
})


# --- Initialisation de la détection au démarrage ---
if (-not [string]::IsNullOrEmpty($Config.ToolsPath)) {
    if (Test-Path $Config.ToolsPath -ErrorAction SilentlyContinue) {
        # Outils trouvés localement ou configurés à l'avance, ignorer l'overlay
        Update-ToolStatuses $Config.ToolsPath
        $WPF_PathSelectorOverlay.Visibility = [System.Windows.Visibility]::Collapsed
        $WPF_MainAppLayout.Visibility = [System.Windows.Visibility]::Visible
        Run-Diagnostics
    }
}

# Lancer la boucle WPF
$Form.ShowDialog() | Out-Null
