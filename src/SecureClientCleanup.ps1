#requires -version 5.1
<# 
  Cisco Cleanup Toolkit — FirstBitEdition (GUI)
  - Очистка Cisco AnyConnect (службы/процессы/папки/реестр)
  - Очистка AppData: текущий или все профили
  - Диагностика конфликтов (другие VPN, GoodbyeDPI/WinDivert, прокси, адаптеры, маршруты)
  - Действия: отключить подозрительные адаптеры; остановить GoodbyeDPI/WinDivert и VPN-перехватчики
  - Ping vpn.1cbit.ru с корректной кодировкой
  - Экспорт HTML/CSV/JSON
#>

# ── Bootstrap: elevation + STA ─────────────────────────────────────────────────
$script:OriginalArgumentList = @($args)
$script:SelfScriptPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }

function Test-IsAdministrator {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsStaThread {
  return ([Threading.Thread]::CurrentThread.ApartmentState -eq 'STA')
}

function Join-ArgumentList([string[]]$Arguments) {
  $quoted = foreach ($arg in $Arguments) {
    if ($null -eq $arg) { '""'; continue }

    $value = [string]$arg
    if ($value.Length -eq 0) { '""'; continue }
    if ($value -notmatch '[\s"]') { $value; continue }

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($ch in $value.ToCharArray()) {
      if ($ch -eq '\') {
        $backslashes++
      } elseif ($ch -eq '"') {
        [void]$builder.Append('\' * ($backslashes * 2 + 1))
        [void]$builder.Append('"')
        $backslashes = 0
      } else {
        if ($backslashes -gt 0) {
          [void]$builder.Append('\' * $backslashes)
          $backslashes = 0
        }
        [void]$builder.Append($ch)
      }
    }
    if ($backslashes -gt 0) {
      [void]$builder.Append('\' * ($backslashes * 2))
    }
    [void]$builder.Append('"')
    $builder.ToString()
  }

  return ($quoted -join ' ')
}

function Get-SelfLaunchInfo {
  $processPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $processName = Split-Path -Path $processPath -Leaf
  $scriptPath = $script:SelfScriptPath
  $isPowerShellHost = $processName -in @('powershell.exe','powershell_ise.exe','pwsh.exe')
  $isScriptLaunch = $isPowerShellHost -and
                    -not [string]::IsNullOrWhiteSpace($scriptPath) -and
                    ([IO.Path]::GetExtension($scriptPath) -ieq '.ps1')

  if ($isScriptLaunch) {
    return [PSCustomObject]@{
      Kind = 'Script'
      FilePath = 'powershell.exe'
      ScriptPath = [IO.Path]::GetFullPath($scriptPath)
      Arguments = @($script:OriginalArgumentList)
    }
  }

  return [PSCustomObject]@{
    Kind = 'Executable'
    FilePath = $processPath
    ScriptPath = $null
    Arguments = @($script:OriginalArgumentList)
  }
}

function Restart-ScriptElevated {
  $self = Get-SelfLaunchInfo
  $psi = New-Object System.Diagnostics.ProcessStartInfo

  # .ps1 must be relaunched through powershell.exe with -File; ps2exe builds must
  # relaunch the compiled executable itself, otherwise UAC can open an empty host.
  if ($self.Kind -eq 'Script') {
    $psi.FileName = $self.FilePath
    $psi.Arguments = Join-ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$self.ScriptPath) + $self.Arguments)
  } else {
    $psi.FileName = $self.FilePath
    $psi.Arguments = Join-ArgumentList $self.Arguments
  }

  $psi.Verb = 'runas'
  $psi.UseShellExecute = $true
  [System.Diagnostics.Process]::Start($psi) | Out-Null
}

function Restart-ScriptInSta {
  $self = Get-SelfLaunchInfo
  $psi = New-Object System.Diagnostics.ProcessStartInfo

  # WPF requires an STA thread because its dispatcher and COM-backed UI objects
  # are apartment-affine. For .ps1 we can force STA via powershell.exe -STA.
  if ($self.Kind -eq 'Script') {
    $psi.FileName = $self.FilePath
    $psi.Arguments = Join-ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-STA','-File',$self.ScriptPath) + $self.Arguments)
  } else {
    $psi.FileName = $self.FilePath
    $psi.Arguments = Join-ArgumentList $self.Arguments
  }

  $psi.UseShellExecute = $true
  [System.Diagnostics.Process]::Start($psi) | Out-Null
}

try {
  if (-not (Test-IsAdministrator)) {
    Restart-ScriptElevated
    exit
  }

  if (-not (Test-IsStaThread)) {
    Restart-ScriptInSta
    exit
  }
} catch {
  try {
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    [System.Windows.Forms.MessageBox]::Show("Не удалось перезапустить с нужными правами/STA: $($_.Exception.Message)","Cisco Cleanup","OK","Error") | Out-Null
  } catch {
    Write-Error ("Не удалось перезапустить с нужными правами/STA: {0}" -f $_.Exception.Message)
  }
  exit 1
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms

# ── UI (WPF XAML) ──────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Secure Client Cleanup Utility" Height="820" Width="1280"
        MinHeight="760" MinWidth="1180" WindowStartupLocation="CenterScreen"
        Background="#0B1020" Foreground="#E5E7EB" FontFamily="Segoe UI">
  <Window.Resources>
    <ResourceDictionary>
      <Color x:Key="ColorBg">#0B1020</Color>
      <Color x:Key="ColorPanel">#111827</Color>
      <Color x:Key="ColorPanelAlt">#162033</Color>
      <Color x:Key="ColorCard">#172033</Color>
      <Color x:Key="ColorCardSoft">#1B2A44</Color>
      <Color x:Key="ColorBorder">#31435F</Color>
      <Color x:Key="ColorText">#E5E7EB</Color>
      <Color x:Key="ColorMuted">#94A3B8</Color>
      <Color x:Key="ColorAccent">#38BDF8</Color>
      <Color x:Key="ColorSuccess">#22C55E</Color>
      <Color x:Key="ColorWarn">#F59E0B</Color>
      <Color x:Key="ColorDanger">#EF4444</Color>

      <SolidColorBrush x:Key="BrushBg" Color="{StaticResource ColorBg}"/>
      <SolidColorBrush x:Key="BrushPanel" Color="{StaticResource ColorPanel}"/>
      <SolidColorBrush x:Key="BrushPanelAlt" Color="{StaticResource ColorPanelAlt}"/>
      <SolidColorBrush x:Key="BrushCard" Color="{StaticResource ColorCard}"/>
      <SolidColorBrush x:Key="BrushCardSoft" Color="{StaticResource ColorCardSoft}"/>
      <SolidColorBrush x:Key="BrushBorder" Color="{StaticResource ColorBorder}"/>
      <SolidColorBrush x:Key="BrushText" Color="{StaticResource ColorText}"/>
      <SolidColorBrush x:Key="BrushMuted" Color="{StaticResource ColorMuted}"/>
      <SolidColorBrush x:Key="BrushAccent" Color="{StaticResource ColorAccent}"/>
      <SolidColorBrush x:Key="BrushSuccess" Color="{StaticResource ColorSuccess}"/>
      <SolidColorBrush x:Key="BrushWarn" Color="{StaticResource ColorWarn}"/>
      <SolidColorBrush x:Key="BrushDanger" Color="{StaticResource ColorDanger}"/>

      <Style TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
      </Style>

      <Style x:Key="TitleText" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="FontSize" Value="26"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
      </Style>

      <Style x:Key="SectionTitle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="FontSize" Value="15"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Margin" Value="0,0,0,8"/>
      </Style>

      <Style x:Key="MutedText" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushMuted}"/>
        <Setter Property="FontSize" Value="12"/>
      </Style>

      <Style x:Key="Card" TargetType="Border">
        <Setter Property="Background" Value="{StaticResource BrushCard}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CornerRadius" Value="14"/>
        <Setter Property="Padding" Value="12"/>
        <Setter Property="Margin" Value="0,0,0,10"/>
      </Style>

      <Style x:Key="SoftCard" TargetType="Border" BasedOn="{StaticResource Card}">
        <Setter Property="Background" Value="{StaticResource BrushCardSoft}"/>
        <Setter Property="BorderBrush" Value="#3B5275"/>
        <Setter Property="CornerRadius" Value="12"/>
        <Setter Property="Padding" Value="10"/>
      </Style>

      <Style TargetType="Button">
        <Setter Property="Background" Value="#22304A"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="#3B5275"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="12,8"/>
        <Setter Property="MinHeight" Value="36"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="10" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter Property="Background" Value="#2F456A"/>
                  <Setter Property="BorderBrush" Value="{StaticResource BrushAccent}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter Property="Background" Value="#1B2A44"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                  <Setter Property="Opacity" Value="0.45"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#0EA5E9"/>
        <Setter Property="BorderBrush" Value="#38BDF8"/>
        <Setter Property="Foreground" Value="#F8FAFC"/>
      </Style>

      <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#7F1D1D"/>
        <Setter Property="BorderBrush" Value="#EF4444"/>
      </Style>

      <Style TargetType="CheckBox">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="Margin" Value="0,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="CheckBox">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="22"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" Background="#0F172A"
                        BorderBrush="#4B6284" BorderThickness="1.2" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                <Path x:Name="CheckMark" Grid.Column="0" Data="M 3 8 L 7 12 L 14 4" Stroke="#FFFFFF" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
                <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
              </Grid>
              <ControlTemplate.Triggers>
                <Trigger Property="IsChecked" Value="True">
                  <Setter TargetName="Box" Property="Background" Value="{StaticResource BrushAccent}"/>
                  <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource BrushAccent}"/>
                  <Setter TargetName="CheckMark" Property="Visibility" Value="Visible"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Box" Property="BorderBrush" Value="#7DD3FC"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                  <Setter Property="Opacity" Value="0.45"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style TargetType="RadioButton">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="Margin" Value="0,5"/>
        <Setter Property="FontSize" Value="13"/>
        <Setter Property="VerticalContentAlignment" Value="Center"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="RadioButton">
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="22"/>
                  <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Ellipse x:Name="Ring" Width="16" Height="16" Stroke="#4B6284" StrokeThickness="1.3" Fill="#0F172A"
                         HorizontalAlignment="Left" VerticalAlignment="Center"/>
                <Ellipse x:Name="Dot" Width="8" Height="8" Fill="{StaticResource BrushAccent}" HorizontalAlignment="Left"
                         VerticalAlignment="Center" Margin="4,0,0,0" Visibility="Collapsed"/>
                <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
              </Grid>
              <ControlTemplate.Triggers>
                <Trigger Property="IsChecked" Value="True">
                  <Setter TargetName="Ring" Property="Stroke" Value="{StaticResource BrushAccent}"/>
                  <Setter TargetName="Dot" Property="Visibility" Value="Visible"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="Ring" Property="Stroke" Value="#7DD3FC"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style TargetType="TextBox">
        <Setter Property="Background" Value="#0F172A"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="8"/>
        <Setter Property="CaretBrush" Value="{StaticResource BrushAccent}"/>
      </Style>

      <Style x:Key="ConsoleTextBox" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
        <Setter Property="Background" Value="#07111F"/>
        <Setter Property="Foreground" Value="#D1E7FF"/>
        <Setter Property="BorderBrush" Value="#27415F"/>
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="Padding" Value="10"/>
      </Style>

      <Style TargetType="DataGrid">
        <Setter Property="Background" Value="#0F172A"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="RowBackground" Value="#111827"/>
        <Setter Property="AlternatingRowBackground" Value="#162033"/>
        <Setter Property="GridLinesVisibility" Value="Horizontal"/>
        <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="VerticalGridLinesBrush" Value="{StaticResource BrushBorder}"/>
      </Style>

      <Style TargetType="DataGridColumnHeader">
        <Setter Property="Background" Value="#1E293B"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Padding" Value="10,8"/>
      </Style>

      <Style TargetType="DataGridCell">
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="Padding" Value="8,5"/>
      </Style>

      <Style TargetType="ProgressBar">
        <Setter Property="Height" Value="8"/>
        <Setter Property="Background" Value="#1E293B"/>
        <Setter Property="Foreground" Value="{StaticResource BrushAccent}"/>
      </Style>

      <Style TargetType="ScrollBar">
        <Setter Property="Background" Value="#0F172A"/>
        <Setter Property="Width" Value="8"/>
        <Setter Property="MinWidth" Value="8"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="ScrollBar">
              <Grid Background="#0B1020" Width="8">
                <Track x:Name="PART_Track" IsDirectionReversed="True">
                  <Track.DecreaseRepeatButton>
                    <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" IsTabStop="False"/>
                  </Track.DecreaseRepeatButton>
                  <Track.Thumb>
                    <Thumb>
                      <Thumb.Template>
                        <ControlTemplate TargetType="Thumb">
                          <Border Background="#334155" CornerRadius="4" Margin="2,0"/>
                        </ControlTemplate>
                      </Thumb.Template>
                    </Thumb>
                  </Track.Thumb>
                  <Track.IncreaseRepeatButton>
                    <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" IsTabStop="False"/>
                  </Track.IncreaseRepeatButton>
                </Track>
              </Grid>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style x:Key="NavItem" TargetType="Border">
        <Setter Property="CornerRadius" Value="10"/>
        <Setter Property="Padding" Value="12,9"/>
        <Setter Property="Margin" Value="0,3"/>
        <Setter Property="MinHeight" Value="40"/>
        <Setter Property="Background" Value="Transparent"/>
      </Style>

      <Style x:Key="NavItemSelected" TargetType="Border" BasedOn="{StaticResource NavItem}">
        <Setter Property="Background" Value="#183352"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushAccent}"/>
        <Setter Property="BorderThickness" Value="1"/>
      </Style>
    </ResourceDictionary>
  </Window.Resources>

  <Grid Background="{StaticResource BrushBg}">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="230"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="300"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="#0F172A" BorderBrush="{StaticResource BrushBorder}" BorderThickness="0,0,1,0" Padding="18">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <StackPanel>
          <Border Width="62" Height="62" CornerRadius="14" Background="#123047" BorderBrush="{StaticResource BrushAccent}" BorderThickness="1" HorizontalAlignment="Left" Margin="0,0,0,14">
            <Grid>
              <TextBlock Text="SC" FontSize="20" FontWeight="Bold" Foreground="{StaticResource BrushAccent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Grid>
          </Border>
          <TextBlock Text="Secure Client" FontSize="20" FontWeight="SemiBold"/>
          <TextBlock Text="Cleanup Utility" Style="{StaticResource MutedText}" Margin="0,2,0,20"/>

          <Border Style="{StaticResource SoftCard}" Margin="0,0,0,18">
            <StackPanel>
              <TextBlock Text="Safety-first cleanup" FontWeight="SemiBold"/>
              <TextBlock Text="Dry Run is the default path. Broad Cisco roots stay blocked." Style="{StaticResource MutedText}" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>

        <StackPanel Grid.Row="1" Margin="0,6,0,0">
          <Border Style="{StaticResource NavItemSelected}"><TextBlock Text="Overview" FontWeight="SemiBold" Foreground="{StaticResource BrushAccent}"/></Border>
          <Border Style="{StaticResource NavItem}"><TextBlock Text="Cleanup"/></Border>
          <Border Style="{StaticResource NavItem}"><TextBlock Text="Diagnostics"/></Border>
          <Border Style="{StaticResource NavItem}"><TextBlock Text="Reports"/></Border>
          <Border Style="{StaticResource NavItem}"><TextBlock Text="Settings"/></Border>
        </StackPanel>

        <StackPanel Grid.Row="2">
          <Border CornerRadius="10" Background="#12351F" BorderBrush="#2B7A44" BorderThickness="1" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="System healthy" Foreground="{StaticResource BrushSuccess}" FontWeight="SemiBold"/>
              <TextBlock Text="Safe defaults active" Style="{StaticResource MutedText}" Margin="0,3,0,0"/>
            </StackPanel>
          </Border>
          <TextBlock Text="Version" Style="{StaticResource MutedText}"/>
          <TextBlock Text="Build: local PowerShell 5.1" Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Column="1" Margin="20,18,18,18">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <Grid Grid.Row="0" Margin="0,0,0,12">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*" MinWidth="430"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0" Margin="0,0,24,0">
          <TextBlock Text="Secure Client Cleanup Utility" Style="{StaticResource TitleText}" TextWrapping="NoWrap"/>
          <TextBlock Text="Modern safety dashboard for Cisco AnyConnect / Secure Client reinstall preparation" Style="{StaticResource MutedText}" Margin="0,4,0,0" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="btnAnalyze" Content="Dry Run / WhatIf" Style="{StaticResource AccentButton}" Width="142" Height="38" Margin="0,0,8,0"/>
          <Button x:Name="btnRun" Content="Cleanup" Style="{StaticResource DangerButton}" Width="96" Height="38" Margin="0,0,8,0"/>
          <Button x:Name="btnClose" Content="Close" Width="76" Height="38"/>
        </StackPanel>
      </Grid>

      <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="0,0,6,0" Background="Transparent">
        <StackPanel>
          <Grid Margin="0,0,0,12">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border Style="{StaticResource Card}" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="Device Ready" Style="{StaticResource SectionTitle}"/>
                <TextBlock Text="Admin + STA bootstrap active" Style="{StaticResource MutedText}"/>
                <TextBlock Text="Ready" Foreground="{StaticResource BrushSuccess}" FontSize="20" FontWeight="SemiBold" Margin="0,6,0,0"/>
              </StackPanel>
            </Border>
            <Border Grid.Column="1" Style="{StaticResource Card}" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="Safety State" Style="{StaticResource SectionTitle}"/>
                <TextBlock Text="Broad Cisco roots are blocked" Style="{StaticResource MutedText}"/>
                <TextBlock Text="Protected" Foreground="{StaticResource BrushAccent}" FontSize="20" FontWeight="SemiBold" Margin="0,6,0,0"/>
              </StackPanel>
            </Border>
            <Border Grid.Column="2" Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Last Scan" Style="{StaticResource SectionTitle}"/>
                <TextBlock x:Name="lblSummary" Text="Nothing scanned yet" Style="{StaticResource MutedText}"/>
                <ProgressBar x:Name="pb" Minimum="0" Maximum="100" Margin="0,12,0,0"/>
              </StackPanel>
            </Border>
          </Grid>

          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="Safe Workflow" Style="{StaticResource SectionTitle}"/>
              <UniformGrid Columns="6" Rows="1">
                <Border Style="{StaticResource SoftCard}" Margin="0,0,8,0"><StackPanel><TextBlock Text="01" Style="{StaticResource MutedText}"/><TextBlock Text="Scan" FontWeight="SemiBold"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Margin="0,0,8,0"><StackPanel><TextBlock Text="02" Style="{StaticResource MutedText}"/><TextBlock Text="Dry Run" FontWeight="SemiBold"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Margin="0,0,8,0"><StackPanel><TextBlock Text="03" Style="{StaticResource MutedText}"/><TextBlock Text="Backup" FontWeight="SemiBold"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Margin="0,0,8,0"><StackPanel><TextBlock Text="04" Style="{StaticResource MutedText}"/><TextBlock Text="Cleanup" FontWeight="SemiBold"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Margin="0,0,8,0"><StackPanel><TextBlock Text="05" Style="{StaticResource MutedText}"/><TextBlock Text="Reboot" FontWeight="SemiBold"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}"><StackPanel><TextBlock Text="06" Style="{StaticResource MutedText}"/><TextBlock Text="Reinstall" FontWeight="SemiBold"/></StackPanel></Border>
              </UniformGrid>
            </StackPanel>
          </Border>

          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="1.2*"/>
              <ColumnDefinition Width="1*"/>
            </Grid.ColumnDefinitions>

            <Border Style="{StaticResource Card}" Margin="0,0,12,12">
              <StackPanel>
                <TextBlock Text="Safety Controls" Style="{StaticResource SectionTitle}"/>
                <Grid>
                  <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="1*"/>
                    <ColumnDefinition Width="1.25*"/>
                  </Grid.ColumnDefinitions>
                  <StackPanel>
                    <CheckBox x:Name="cbWhatIf" Content="WhatIf / Dry Run" IsChecked="True"/>
                    <CheckBox x:Name="cbFull" Content="Full cleanup" IsChecked="False"/>
                    <CheckBox x:Name="cbServices" Content="Services / processes"/>
                    <CheckBox x:Name="cbFolders" Content="Folders and AppData"/>
                    <CheckBox x:Name="cbRegistry" Content="Registry"/>
                  </StackPanel>
                  <StackPanel Grid.Column="1" Margin="18,0,0,0">
                    <RadioButton x:Name="rbCurrent" Content="Current user only" IsChecked="True"/>
                    <RadioButton x:Name="rbAll" Content="All user profiles"/>
                    <CheckBox x:Name="cbBackup" Content="Backup registry / folders"/>
                    <CheckBox x:Name="cbHtml" Content="HTML report" IsChecked="True"/>
                    <CheckBox x:Name="cbForce" Content="Force retry"/>
                    <CheckBox x:Name="cbRestorePoint" Content="Create restore point" IsChecked="False"/>
                    <CheckBox x:Name="cbSelectionOnly" Content="Selected rows only"/>
                    <CheckBox x:Name="cbOnlyFound" Content="Show only found"/>
                  </StackPanel>
                </Grid>
              </StackPanel>
            </Border>

            <Border Grid.Column="1" Style="{StaticResource Card}">
              <StackPanel>
                <TextBlock Text="Diagnostics Quick Actions" Style="{StaticResource SectionTitle}"/>
                <Button x:Name="btnDiag" Content="Run Diagnostics" Margin="0,0,0,8"/>
                <Button x:Name="btnDisableAdapters" Content="Disable suspicious adapters" Margin="0,0,0,8"/>
                <Button x:Name="btnStopGoodbye" Content="Stop GoodbyeDPI / WinDivert" Margin="0,0,0,8"/>
                <Button x:Name="btnPing" Content="Ping vpn.1cbit.ru"/>
              </StackPanel>
            </Border>
          </Grid>

          <Border Style="{StaticResource Card}">
            <StackPanel>
              <TextBlock Text="Detected Components" Style="{StaticResource SectionTitle}"/>
              <UniformGrid Columns="6" Rows="1">
                <Border Style="{StaticResource SoftCard}" Height="76" Padding="8" Margin="0,0,8,0"><StackPanel><TextBlock Text="Services" Style="{StaticResource MutedText}"/><TextBlock Text="3" FontSize="19" FontWeight="SemiBold"/><TextBlock Text="targets" Style="{StaticResource MutedText}"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Height="76" Padding="8" Margin="0,0,8,0"><StackPanel><TextBlock Text="Folders" Style="{StaticResource MutedText}"/><TextBlock Text="Scoped" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="known paths" Style="{StaticResource MutedText}"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Height="76" Padding="8" Margin="0,0,8,0"><StackPanel><TextBlock Text="Registry" Style="{StaticResource MutedText}"/><TextBlock Text="Service" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="keys only" Style="{StaticResource MutedText}"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Height="76" Padding="8" Margin="0,0,8,0"><StackPanel><TextBlock Text="AppData" Style="{StaticResource MutedText}"/><TextBlock Text="User" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="scoped" Style="{StaticResource MutedText}"/></StackPanel></Border>
                <Border Style="{StaticResource SoftCard}" Height="76" Padding="8" Margin="0,0,8,0"><StackPanel><TextBlock Text="Diagnostics" Style="{StaticResource MutedText}"/><TextBlock Text="Ready" FontSize="15" FontWeight="SemiBold"/><TextBlock Text="network" Style="{StaticResource MutedText}"/></StackPanel></Border>
                <Border Height="76" Background="#123047" BorderBrush="{StaticResource BrushAccent}" BorderThickness="1" CornerRadius="12" Padding="8"><StackPanel><TextBlock Text="Total" Style="{StaticResource MutedText}"/><TextBlock Text="Scan" FontSize="19" FontWeight="SemiBold" Foreground="{StaticResource BrushAccent}"/><TextBlock Text="first" Style="{StaticResource MutedText}"/></StackPanel></Border>
              </UniformGrid>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}">
            <Grid>
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="260"/>
              </Grid.RowDefinitions>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>
              <TextBlock Text="Scan Results" Style="{StaticResource SectionTitle}"/>
              <StackPanel Grid.Column="1" Orientation="Horizontal" Margin="0,0,0,10">
                <Button x:Name="btnScan" Content="Scan" Style="{StaticResource AccentButton}" Width="90" Margin="0,0,8,0"/>
                <Button x:Name="btnExportCsv" Content="CSV" Width="70" Margin="0,0,8,0"/>
                <Button x:Name="btnExportJson" Content="JSON" Width="70" Margin="0,0,8,0"/>
                <Button x:Name="btnExportHtml" Content="HTML" Width="70"/>
              </StackPanel>

              <DataGrid x:Name="dgScan" Grid.Row="1" Grid.ColumnSpan="2" AutoGenerateColumns="False" CanUserAddRows="False"
                        HeadersVisibility="Column" SelectionMode="Extended" SelectionUnit="FullRow">
                <DataGrid.Columns>
                  <DataGridCheckBoxColumn Header="Sel" Binding="{Binding Selected}" Width="48"/>
                  <DataGridTextColumn Header="Category" Binding="{Binding Category}" Width="140"/>
                  <DataGridTextColumn Header="Name" Binding="{Binding Name}" Width="*"/>
                  <DataGridTextColumn Header="State" Binding="{Binding State}" Width="140"/>
                  <DataGridTextColumn Header="Details" Binding="{Binding Details}" Width="260"/>
                </DataGrid.Columns>
              </DataGrid>
            </Grid>
          </Border>

          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <Border Style="{StaticResource Card}" Margin="0,0,12,0">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="120"/>
                </Grid.RowDefinitions>
                <TextBlock Text="Activity Log" Style="{StaticResource SectionTitle}"/>
                <TextBox x:Name="tbConsole" Grid.Row="1" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         Style="{StaticResource ConsoleTextBox}" IsReadOnly="True"/>
              </Grid>
            </Border>
            <Border Grid.Column="1" Style="{StaticResource Card}">
              <Grid>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="120"/>
                </Grid.RowDefinitions>
                <TextBlock Text="Diagnostics Output" Style="{StaticResource SectionTitle}"/>
                <TextBox x:Name="tbDiag" Grid.Row="1" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         Style="{StaticResource ConsoleTextBox}" IsReadOnly="True"/>
              </Grid>
            </Border>
          </Grid>
        </StackPanel>
      </ScrollViewer>

      <Border Grid.Row="2" Style="{StaticResource Card}" Margin="0,14,0,0" Padding="12">
        <TextBox x:Name="tbLogView" Height="54" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                 FontFamily="Consolas" FontSize="12"/>
      </Border>
    </Grid>

    <Border Grid.Column="2" Background="{StaticResource BrushPanel}" BorderBrush="{StaticResource BrushBorder}" BorderThickness="1,0,0,0" Padding="16">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="0,0,4,0">
        <StackPanel>
          <TextBlock Text="Summary" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,12"/>

          <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,0,9">
            <StackPanel>
              <TextBlock Text="Items Found" Style="{StaticResource MutedText}"/>
              <TextBlock Text="Run Scan" FontSize="20" FontWeight="SemiBold" Margin="0,3,0,0"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,0,9">
            <StackPanel>
              <TextBlock Text="Blocked Broad Roots" Style="{StaticResource MutedText}"/>
              <TextBlock Text="Registry + folders protected" Foreground="{StaticResource BrushSuccess}" FontWeight="SemiBold" Margin="0,3,0,0"/>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,0,9">
            <StackPanel>
              <TextBlock Text="Backup Path" Style="{StaticResource MutedText}"/>
              <TextBlock Text="Log path" FontWeight="SemiBold" Margin="0,3,0,5"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox x:Name="tbLogPath" Text="%ProgramData%\CiscoCleanup\cleanup.log" Height="36" VerticalContentAlignment="Center" HorizontalScrollBarVisibility="Hidden" TextWrapping="NoWrap"/>
                <Button x:Name="btnOpenLog" Grid.Column="1" Content="Open" Width="58" Height="36" Margin="6,0,0,0"/>
              </Grid>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,0,9">
            <StackPanel>
              <TextBlock Text="Report Path" Style="{StaticResource MutedText}"/>
              <TextBlock Text="HTML report" FontWeight="SemiBold" Margin="0,3,0,5"/>
              <Grid>
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="*"/>
                  <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <TextBox x:Name="tbHtmlPath" Text="%ProgramData%\CiscoCleanup\report.html" Height="36" VerticalContentAlignment="Center" HorizontalScrollBarVisibility="Hidden" TextWrapping="NoWrap"/>
                <Button x:Name="btnOpenHtml" Grid.Column="1" Content="Open" Width="58" Height="36" Margin="6,0,0,0"/>
              </Grid>
            </StackPanel>
          </Border>

          <Border Style="{StaticResource Card}" Padding="12" Margin="0,0,0,9">
            <StackPanel>
              <TextBlock Text="Current Plan" Style="{StaticResource MutedText}"/>
              <TextBlock Text="1. Scan" Margin="0,6,0,0"/>
              <TextBlock Text="2. Dry Run / WhatIf" Margin="0,2,0,0"/>
              <TextBlock Text="3. Backup" Margin="0,2,0,0"/>
              <TextBlock Text="4. Cleanup" Margin="0,2,0,0"/>
              <TextBlock Text="5. Reboot" Margin="0,2,0,0"/>
              <TextBlock Text="6. Reinstall Cisco Secure Client" Margin="0,2,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
      </ScrollViewer>
    </Border>
  </Grid>
</Window>
'@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$nsMgr = New-Object System.Xml.XmlNamespaceManager($xaml.NameTable)
$nsMgr.AddNamespace("x","http://schemas.microsoft.com/winfx/2006/xaml")
$controls = @{}
$xaml.SelectNodes("//*[@x:Name]", $nsMgr) | ForEach-Object {
  $n = $_.Attributes["x:Name"].Value
  $controls[$n] = $window.FindName($n)
}

function Resolve-Env($p){ [Environment]::ExpandEnvironmentVariables($p) }
$global:CleanupRoot = Join-Path $env:ProgramData "CiscoCleanup"; New-Item -ItemType Directory -Force -Path $global:CleanupRoot | Out-Null

# ── Логирование ────────────────────────────────────────────────────────────────
function Ensure-LogPath($LogPath){
  $dir = Split-Path -Path $LogPath -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (-not (Test-Path $LogPath)) { New-Item -ItemType File -Force -Path $LogPath | Out-Null }
}
function Write-UILog([string]$Message,[string]$Level="INFO"){
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts][$Level] $Message"
  if ($controls.tbConsole){ $controls.tbConsole.AppendText($line + [Environment]::NewLine); $controls.tbConsole.ScrollToEnd() }
  $logPath = Resolve-Env $controls.tbLogPath.Text; Ensure-LogPath $logPath; Add-Content -Path $logPath -Value $line
  if ($controls.tbLogView){ $controls.tbLogView.AppendText($line + [Environment]::NewLine); $controls.tbLogView.ScrollToEnd() }
}
function Write-Diag([string]$Message){
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] $Message"
  if ($controls.tbDiag){ $controls.tbDiag.AppendText($line + [Environment]::NewLine); $controls.tbDiag.ScrollToEnd() }
  Write-UILog $Message "DIAG"
}

# ── Цели очистки ───────────────────────────────────────────────────────────────
$Services   = @("vpnagent","cvpnd","vpnva")
$Processes  = @("vpnui","vpnagent","cvpnd","ciscoap")
$ProgramFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')

$RegistryKeys = @(
  "HKLM:\SYSTEM\CurrentControlSet\Services\vpnagent",
  "HKLM:\SYSTEM\CurrentControlSet\Services\cvpnd",
  "HKLM:\SYSTEM\CurrentControlSet\Services\vpnva"
)

$ProgramFolderNames = @(
  "Cisco AnyConnect Secure Mobility Client",
  "Cisco AnyConnect",
  "Cisco Secure Client",
  "Cisco Secure Client\VPN",
  "Cisco Secure Client\ISE Posture",
  "Cisco Secure Client\Diagnostics and Reporting Tool",
  "Cisco Secure Client\Umbrella",
  "Cisco Secure Client\Network Access Manager"
)
$ProgramFolders = @(
  foreach($name in $ProgramFolderNames) {
    if ($env:ProgramFiles) { Join-Path $env:ProgramFiles $name }
    if ($ProgramFilesX86) { Join-Path $ProgramFilesX86 $name }
  }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

$BlockedRegistryRoots = @(
  "HKLM:\SOFTWARE\Cisco",
  "HKLM:\SOFTWARE\WOW6432Node\Cisco",
  "HKCU:\Software\Cisco"
)
$BlockedFolderRoots = @(
  if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "Cisco" }
  if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "Cisco Systems" }
  if ($ProgramFilesX86) { Join-Path $ProgramFilesX86 "Cisco" }
  if ($ProgramFilesX86) { Join-Path $ProgramFilesX86 "Cisco Systems" }
  if ($env:ProgramData) { Join-Path $env:ProgramData "Cisco" }
  if ($env:ProgramData) { Join-Path $env:ProgramData "Cisco Systems" }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

function Normalize-SafetyPath([string]$Path){
  if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
  return ([Environment]::ExpandEnvironmentVariables($Path).TrimEnd('\')).ToLowerInvariant()
}
function Test-IsBlockedCleanupTarget([string]$Target,[string]$Kind){
  $normalized = Normalize-SafetyPath $Target
  $blocked = if ($Kind -eq "Registry") { $BlockedRegistryRoots } else { $BlockedFolderRoots }
  foreach($root in $blocked){
    if ($normalized -eq (Normalize-SafetyPath $root)) { return $true }
  }
  return $false
}
function Test-IsBlockedRegistryRoot([string]$Key){
  return (Test-IsBlockedCleanupTarget -Target $Key -Kind "Registry")
}
function Test-IsBlockedFolderRoot([string]$Path){
  return (Test-IsBlockedCleanupTarget -Target $Path -Kind "Folder")
}

# ── Профили пользователей ─────────────────────────────────────────────────────
function Get-UserProfiles {
  $out = @()
  $reg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
  Get-ChildItem $reg -ErrorAction SilentlyContinue | ForEach-Object {
    $p = (Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue).ProfileImagePath
    if ($p -and (Test-Path $p)) {
      $leaf = Split-Path $p -Leaf
      if ($leaf -in @("Default","Default User","Public","All Users")) { return }
      $out += $p
    }
  }
  if ($env:USERPROFILE) { $out += $env:USERPROFILE }
  $out | Sort-Object -Unique
}

# ── Список папок (включая AppData по всем профилям при выборе «Все») ──────────
# ЗАМЕНА функции Get-TargetFolders
function Get-TargetFolders {
  $folders = [System.Collections.Generic.List[string]]::new()

  # системные каталоги Cisco
  foreach ($p in $ProgramFolders) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    $folders.Add([string]$p)
  }

  # профили пользователей
  $profiles = @(Get-UserProfiles) | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

  if ($controls.rbAll.IsChecked) {
    foreach ($up in $profiles) {
      try {
        $folders.Add([System.IO.Path]::Combine($up, 'AppData','Roaming','Cisco'))
        $folders.Add([System.IO.Path]::Combine($up, 'AppData','Local','Cisco'))
      } catch {
        # просто пропускаем проблемный профиль
        Write-UILog ("Skip profile {0}: {1}" -f $up, $_.Exception.Message) "WARN"
      }
    }
  } else {
    $folders.Add([System.IO.Path]::Combine([string]$env:APPDATA, 'Cisco'))
    $folders.Add([System.IO.Path]::Combine([string]$env:LOCALAPPDATA, 'Cisco'))
  }

  # уникализируем и возвращаем массив строк
  return $folders | Where-Object { $_ } | Sort-Object -Unique
}

function Update-Progress($v){ if ($controls.pb){ $controls.pb.Value=[double]$v } }

# ── Ping в CP866 (чтоб не было «кракозябр») ────────────────────────────────────
function Invoke-PingFirstBit {
  param([string]$Target="vpn.1cbit.ru",[int]$Count=2,[int]$TimeoutMs=2000)
  Write-UILog "Ping $Target ($Count пакетов, таймаут $TimeoutMs мс)"
  try{
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName="ping.exe"
    $psi.Arguments="-n $Count -w $TimeoutMs $Target"
    $psi.RedirectStandardOutput=$true
    $psi.StandardOutputEncoding=[System.Text.Encoding]::GetEncoding(866)
    $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $p=[System.Diagnostics.Process]::Start($psi)
    $out=$p.StandardOutput.ReadToEnd(); $p.WaitForExit()
    $out -split "`r?`n" | % { if($_){ Write-UILog $_ } }
  } catch { Write-UILog ("Ошибка ping: {0}" -f $_.Exception.Message) "ERROR" }
}

# ── SCAN ──────────────────────────────────────────────────────────────────────
function Do-Scan {
  Update-Progress 0
  $raw = New-Object System.Collections.Generic.List[Object]

  foreach ($s in $Services) {
    $srv = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($srv) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Service";Name=$s;State=$srv.Status;Details="StartupType=$($srv.StartType)"}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Service";Name=$s;State="Not found";Details=""}) }
  }
  Update-Progress 20

  foreach ($p in $Processes) {
    $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($procs) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Process";Name=$p;State="Running x$($procs.Count)";Details=($procs|%{"PID="+$_.Id})-join ", "}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Process";Name=$p;State="Not running";Details=""}) }
  }
  Update-Progress 40

  foreach ($f in (Get-TargetFolders)) {
    if (Test-Path $f) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Folder";Name=$f;State="Exists";Details=""}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Folder";Name=$f;State="Not found";Details=""}) }
  }
  Update-Progress 70

  foreach ($rk in $RegistryKeys) {
    if (Test-Path $rk) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Registry";Name=$rk;State="Exists";Details=""}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Registry";Name=$rk;State="Not found";Details=""}) }
  }
  Update-Progress 100

  $items = if ($controls.cbOnlyFound.IsChecked) { $raw | ? { $_.State -notin @("Not found","Not running") } } else { $raw }
  $controls.dgScan.ItemsSource = $items
  $controls.lblSummary.Text = "Показано: $($items.Count) (всего: $($raw.Count))"
  return ,$raw
}

# ── Очистка/удаление (фиксы catch: без интерполяции $_) ───────────────────────
function Stop-CiscoProcesses([bool]$WhatIf,$Selection){ 
  $targets = if ($Selection){ $Selection | ? {$_.Category -eq "Process"} } else { $Processes | % { [PSCustomObject]@{Name=$_} } }
  foreach($t in $targets){
    $procs = Get-Process -Name $t.Name -ErrorAction SilentlyContinue
    foreach($p in $procs){
      if ($WhatIf){ Write-UILog ("WHATIF: stop {0} PID={1}" -f $p.ProcessName, $p.Id) }
      else { try{ Stop-Process -Id $p.Id -Force; Write-UILog ("Stopped {0} PID={1}" -f $p.ProcessName,$p.Id) } catch { Write-UILog ("Fail stop {0}: {1}" -f $p.ProcessName, $_.Exception.Message) "WARN" } }
    }
  }
}
function Stop-CiscoServices([bool]$WhatIf,$Selection){
  $targets = if ($Selection){ $Selection | ? {$_.Category -eq "Service"} } else { $Services | % { [PSCustomObject]@{Name=$_} } }
  foreach($t in $targets){
    $srv = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
    if ($srv){
      if ($WhatIf){ Write-UILog ("WHATIF: stop/disable service {0}" -f $t.Name) }
      else{
        try{
          if ($srv.Status -ne 'Stopped'){ Stop-Service -Name $t.Name -Force -ErrorAction Stop }
          Set-Service -Name $t.Name -StartupType Disabled -ErrorAction SilentlyContinue
          Write-UILog ("Service {0} stopped & disabled" -f $t.Name)
        }
        catch{
          Write-UILog ("Fail service {0}: {1}" -f $t.Name, $_.Exception.Message) "WARN"
        }
      }
    }
  }
}
function Remove-CiscoServices([bool]$WhatIf,$Selection){
  $targets = if ($Selection){ $Selection | ? {$_.Category -eq "Service"} } else { $Services | % { [PSCustomObject]@{Name=$_} } }
  foreach($t in $targets){
    $srv = Get-Service -Name $t.Name -ErrorAction SilentlyContinue
    if ($srv){
      if ($WhatIf){ Write-UILog ("WHATIF: sc delete {0}" -f $t.Name) }
      else{
        try{ & sc.exe delete $($t.Name) | Out-Null; Write-UILog ("Deleted service {0}" -f $t.Name) }
        catch{ Write-UILog ("Fail delete service {0}: {1}" -f $t.Name, $_.Exception.Message) "WARN" }
      }
    }
  }
}
function Remove-CiscoFolders([bool]$WhatIf,[bool]$Backup,[bool]$Force,$Selection){
  $targets = if ($Selection){ $Selection | ? {$_.Category -eq "Folder"} | % { $_.Name } } else { Get-TargetFolders }
  foreach($path in $targets){
    if (Test-IsBlockedFolderRoot $path){
      Write-UILog ("BLOCKED safety: broad Cisco folder will not be removed: {0}" -f $path) "WARN"
      continue
    }
    if (Test-Path $path){
      if ($WhatIf){ Write-UILog ("WHATIF: remove dir {0}" -f $path) }
      else{
        try{
          if ($Backup){
            Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction SilentlyContinue
            $zip = Join-Path $global:CleanupRoot ("{0}_{1:yyyyMMdd_HHmmss}.zip" -f ((Split-Path $path -Leaf) -replace '[^\w\-\.]','_'), (Get-Date))
            [System.IO.Compression.ZipFile]::CreateFromDirectory($path,$zip); Write-UILog ("Backup {0} -> {1}" -f $path,$zip)
          }
          Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
          Write-UILog ("Removed dir {0}" -f $path)
        } catch {
          $err = $_.Exception.Message
          if ($Force){
            try{
              Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | % { $_.Attributes='Normal' }
              Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
              Write-UILog ("Removed dir (retry) {0}" -f $path)
            } catch {
              $err2 = $_.Exception.Message
              Write-UILog ("Fail remove {0}: {1}" -f $path, $err2) "ERROR"
            }
          } else {
            Write-UILog ("Fail remove {0}: {1}" -f $path, $err) "ERROR"
          }
        }
      }
    }
  }
}

function ConvertTo-RegExePath([string]$RegistryPath){
  if ([string]::IsNullOrWhiteSpace($RegistryPath)) { return $null }

  $trimmed = $RegistryPath.Trim()
  if ($trimmed -match '^(HKLM|HKCU|HKCR|HKU|HKCC):\\(.*)$') {
    $hive = $matches[1]
    $subPath = $matches[2]
    if ([string]::IsNullOrWhiteSpace($subPath)) { return $hive }
    return ("{0}\{1}" -f $hive, $subPath)
  }

  return $null
}

function Export-RegistryKeySafe([string]$RegistryPath,[string]$OutputPath){
  try{
    if (-not (Test-Path $RegistryPath)){
      Write-UILog ("Backup reg skipped, key not found: {0}" -f $RegistryPath) "WARN"
      return $false
    }

    $regExePath = ConvertTo-RegExePath $RegistryPath
    if ([string]::IsNullOrWhiteSpace($regExePath)){
      Write-UILog ("Backup reg failed, unsupported registry path: {0}" -f $RegistryPath) "ERROR"
      return $false
    }

    $dir = [System.IO.Path]::GetDirectoryName($OutputPath)
    if (-not [string]::IsNullOrWhiteSpace($dir)){
      New-Item -ItemType Directory -Path $dir -Force -ErrorAction Stop | Out-Null
    }

    $output = & reg.exe export $regExePath $OutputPath /y 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0){
      Write-UILog ("Backup reg failed for {0}: reg.exe exit code {1}; {2}" -f $RegistryPath, $exitCode, (($output | Out-String).Trim())) "ERROR"
      return $false
    }

    if (-not (Test-Path $OutputPath)){
      Write-UILog ("Backup reg failed for {0}: output file was not created: {1}" -f $RegistryPath, $OutputPath) "ERROR"
      return $false
    }

    Write-UILog ("Backup reg {0} -> {1}" -f $RegistryPath,$OutputPath)
    return $true
  } catch {
    Write-UILog ("Backup reg failed for {0}: {1}" -f $RegistryPath, $_.Exception.Message) "ERROR"
    return $false
  }
}

function Remove-CiscoRegistry([bool]$WhatIf,[bool]$Backup,$Selection){
  $targets = if ($Selection){ $Selection | ? {$_.Category -eq "Registry"} | % { $_.Name } } else { $RegistryKeys }
  foreach($key in $targets){
    if (Test-IsBlockedRegistryRoot $key){
      Write-UILog ("BLOCKED safety: broad Cisco registry root will not be removed: {0}" -f $key) "WARN"
      continue
    }
    if (Test-Path $key){
      if ($WhatIf){ Write-UILog ("WHATIF: remove reg {0}" -f $key) }
      else{
        try{
          if ($Backup){
            $safe = ($key -replace '[:\\\/\*?\.<>\| ]','_')
            $export = Join-Path $global:CleanupRoot ("reg_{0}_{1:yyyyMMdd_HHmmss}.reg" -f $safe,(Get-Date))
            if (-not (Export-RegistryKeySafe -RegistryPath $key -OutputPath $export)){
              Write-UILog ("Skip remove reg {0}: backup failed" -f $key) "ERROR"
              continue
            }
          }
          Remove-Item -Path $key -Recurse -Force -ErrorAction Stop
          Write-UILog ("Removed reg {0}" -f $key)
        } catch {
          Write-UILog ("Fail reg {0}: {1}" -f $key, $_.Exception.Message) "ERROR"
        }
      }
    }
  }
}

# ── HTML-отчёт ────────────────────────────────────────────────────────────────
function ConvertTo-HtmlEncodedText($Value){
  if ($null -eq $Value) { return "" }

  return ([string]$Value).
    Replace('&','&amp;').
    Replace('<','&lt;').
    Replace('>','&gt;').
    Replace('"','&quot;').
    Replace("'","&#39;")
}

function Save-HtmlReport([Array]$Items,[string]$Path){
  $reportPath = [System.IO.Path]::GetFullPath($Path)
  $reportDir = [System.IO.Path]::GetDirectoryName($reportPath)
  if (-not [string]::IsNullOrWhiteSpace($reportDir)){
    New-Item -ItemType Directory -Path $reportDir -Force -ErrorAction Stop | Out-Null
  }

  $itemList = if ($null -eq $Items) { @() } else { @($Items) }
  if ($itemList.Count -gt 0){
    $rows = $itemList | % {
      "<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td></tr>" -f `
        (ConvertTo-HtmlEncodedText $_.Category),
        (ConvertTo-HtmlEncodedText $_.Name),
        (ConvertTo-HtmlEncodedText $_.State),
        (ConvertTo-HtmlEncodedText $_.Details)
    } | Out-String
  } else {
    $rows = "<tr><td colspan=""4"">No scan items</td></tr>"
  }

  $reportDate = ConvertTo-HtmlEncodedText ((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))
  $hostName = ConvertTo-HtmlEncodedText ([Environment]::MachineName)
  $html = @"
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="utf-8">
<title>Secure Client Cleanup Report</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;background:#fff;color:#111;margin:20px}
table{border-collapse:collapse;width:100%}
th,td{border:1px solid #D0D7E2;padding:8px;text-align:left;vertical-align:top}
th{background:#EEF2F7}
</style>
</head>
<body>
<h2>Отчёт сканирования</h2>
<p>Дата: $reportDate &bull; Хост: $hostName</p>
<table>
<thead><tr><th>Категория</th><th>Объект</th><th>Состояние</th><th>Детали</th></tr></thead>
<tbody>
$rows
</tbody>
</table>
</body>
</html>
"@
  Set-Content -Path $reportPath -Value $html -Encoding UTF8
}

# ── Диагностика/действия ──────────────────────────────────────────────────────
$VpnProcPatterns = @("openvpn","openvpnserv","ovpn","wireguard","wg","nordvpn","proton","surfshark","expressvpn","outline","forticlient","juniper","checkpoint","pulse","zscaler","windivert","goodbyedpi","sstap","mudfish","windscribe","hideme","vyprvpn","vpnui","vpnagent")
$AdapterPatterns = @("TAP","TUN","Wintun","WireGuard","NordLynx","Juniper","Fortinet","Checkpoint","PANGP","Zscaler","SSTap","Npcap Loopback","Hyper-V Virtual")
$GoodbyeFiles = @("C:\Program Files\GoodbyeDPI","C:\goodbyedpi","C:\Utils\goodbyedpi")
$GoodbyeTasks = @("GoodbyeDPI","Goodbye","goodbyedpi")
$GoodbyeServices = @("WinDivert1.4","WinDivert1.5","WinDivert","goodbyedpi","GoodbyeDPI")

function Test-VpnDiagnostics([string]$TargetHost = "vpn.1cbit.ru"){
  $errors = New-Object System.Collections.Generic.List[string]
  Write-Diag "=== Диагностика VPN для $TargetHost ==="

  # DNS
  try{
    $ips = [System.Net.Dns]::GetHostAddresses($TargetHost) |
           ? { $_.AddressFamily -eq 'InterNetwork' } |
           % { $_.ToString() }
    if($ips){ Write-Diag ("DNS: {0} -> {1}" -f $TargetHost, ($ips -join ', ')) }
    else    { Write-Diag "DNS: адреса не получены"; $errors.Add("DNS") }
  } catch { Write-Diag ("DNS ошибка: {0}" -f $_.Exception.Message); $errors.Add("DNS") }

  # Ping (краткий индикатор)
  try{
    $ok = Test-Connection -ComputerName $TargetHost -Count 2 -Quiet -ErrorAction SilentlyContinue
    Write-Diag ("Ping: " + ($(if($ok){"OK"}else{"FAIL"})))
  } catch {}

  # TCP 443
  try{
    $t = Test-NetConnection -ComputerName $TargetHost -Port 443 -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if($t.TcpTestSucceeded){ Write-Diag ("TCP 443: доступно (RemoteAddress={0})" -f $t.RemoteAddress) }
    else { Write-Diag "TCP 443: недоступно"; $errors.Add("TCP443") }
  } catch { Write-Diag ("TCP443 ошибка: {0}" -f $_.Exception.Message); $errors.Add("TCP443") }

  # Прокси
  try{
    $ie = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -ErrorAction SilentlyContinue
    $winhttp = (netsh winhttp show proxy) 2>$null
    if ($ie.ProxyEnable -eq 1) { Write-Diag ("Прокси (WinINET): {0}" -f $ie.ProxyServer) } else { Write-Diag "Прокси (WinINET): выключен" }
    if ($winhttp -match "Direct access") { Write-Diag "WinHTTP proxy: Direct" }
    else { Write-Diag ("WinHTTP proxy: " + ($winhttp -split "`r?`n" | ? {$_ -match "Proxy Server"})) }
  } catch { Write-Diag ("Проверка прокси: {0}" -f $_.Exception.Message) }

  # Адаптеры/маршруты
  try{
    $ifaces = Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue | ? {$_.ConnectionState -eq "Connected"}
    $def = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select -First 3
    foreach($i in $ifaces){
      $flag = ($AdapterPatterns | ? { $i.InterfaceAlias -like "*$_*" -or $i.InterfaceDescription -like "*$_*" })
      $m = "IF: {0} (Idx={1}; Metric={2})" -f $i.InterfaceAlias,$i.InterfaceIndex,$i.InterfaceMetric
      if ($flag){ Write-Diag ("[!] Подозрительный адаптер: " + $m) } else { Write-Diag ("    " + $m) }
    }
    foreach($r in $def){
      $ifname = (Get-NetIPInterface -InterfaceIndex $r.IfIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceAlias
      Write-Diag ("Маршрут по умолчанию: IfIndex={0} Metric={1} If={2} NextHop={3}" -f $r.IfIndex,$r.RouteMetric,$ifname,$r.NextHop)
    }
  } catch { Write-Diag ("Маршруты/адаптеры: {0}" -f $_.Exception.Message) }

  # Процессы VPN/перехватчики
  try{
    $procs = Get-Process -ErrorAction SilentlyContinue
    $found = @()
    foreach($p in $procs){ foreach($pat in $VpnProcPatterns){ if ($p.ProcessName -like "*$pat*"){ $found += $p.ProcessName; break } } }
    if ($found){ Write-Diag ("[!] Найдены процессы VPN/перехватчиков: {0}" -f (($found | Sort-Object -Unique) -join ", ")) }
    else { Write-Diag "Сторонние VPN-процессы не обнаружены" }
  } catch {}

  # GoodbyeDPI / WinDivert
  try{
    $gf = @(); foreach($d in $GoodbyeFiles){ if (Test-Path $d){ $gf += $d } }
    if ($gf){ Write-Diag ("[!] Найдены каталоги GoodbyeDPI: {0}" -f ($gf -join ", ")) }
    $tasks = @(); foreach($t in $GoodbyeTasks){ $tasks += (Get-ScheduledTask -ErrorAction SilentlyContinue | ? { $_.TaskName -like "*$t*" -or $_.TaskPath -like "*$t*" }) }
    if ($tasks){ Write-Diag ("[!] Найдены задачи планировщика GoodbyeDPI: {0}" -f (($tasks | Select -Expand TaskName -Unique) -join ", ")) }
    $svcs = @(); foreach($s in $GoodbyeServices){ $svcs += (Get-Service -ErrorAction SilentlyContinue | ? { $_.Name -like "*$s*" -or $_.DisplayName -like "*$s*" }) }
    if ($svcs){ Write-Diag ("[!] Найдены сервисы WinDivert/GoodbyeDPI: {0}" -f (($svcs | Select -Expand Name -Unique) -join ", ")) }
    $drv = Get-ChildItem "$env:WINDIR\System32\drivers" -Filter "WinDivert*.sys" -ErrorAction SilentlyContinue
    if ($drv){ Write-Diag ("[!] Найдены драйверы WinDivert: {0}" -f ($drv.Name -join ", ")) }
  } catch {}

  if ($errors.Count -eq 0) { Write-Diag "=== Итог: сеть базово OK. Если Cisco не коннектится — проверьте отмеченные 'подозрительные' пункты выше." }
  else { Write-Diag ("=== Итог: проблемы: " + ($errors -join ", ")) }
}

function Disable-SuspiciousAdapters {
  $ifaces = Get-NetAdapter -Physical:$false -ErrorAction SilentlyContinue
  $targets = @()
  foreach($i in $ifaces){
    foreach($p in $AdapterPatterns){
      if ($i.Name -like "*$p*" -or $i.InterfaceDescription -like "*$p*"){ $targets += $i; break }
    }
  }
  if (-not $targets.Count){ Write-Diag "Подозрительных адаптеров не найдено."; return }
  $msg = "Будут отключены адаптеры:`n" + ($targets | % { "• " + $_.Name } | Out-String)
  $r=[System.Windows.MessageBox]::Show($msg,"Отключить адаптеры?","YesNo","Warning")
  if($r -ne "Yes"){ return }
  foreach($n in $targets){
    try { Disable-NetAdapter -Name $n.Name -Confirm:$false -ErrorAction Stop; Write-Diag ("Отключен адаптер: {0}" -f $n.Name) }
    catch { Write-Diag ("Не удалось отключить {0}: {1}" -f $n.Name, $_.Exception.Message) }
  }
}

function Stop-ConflictTools {
  $stopped=@()

  foreach($s in $GoodbyeServices){
    $svc = Get-Service -ErrorAction SilentlyContinue | ? { $_.Name -like "*$s*" -or $_.DisplayName -like "*$s*" }
    foreach($x in $svc){
      try{
        if ($x.Status -ne 'Stopped'){ Stop-Service -Name $x.Name -Force -ErrorAction SilentlyContinue }
        Set-Service -Name $x.Name -StartupType Disabled -ErrorAction SilentlyContinue
        $stopped += "Service:$($x.Name)"
        Write-Diag ("Остановлен/отключен сервис: {0}" -f $x.Name)
      } catch { Write-Diag ("Не удалось остановить сервис {0}: {1}" -f $x.Name, $_.Exception.Message) }
    }
  }

  foreach($t in $GoodbyeTasks){
    $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue | ? { $_.TaskName -like "*$t*" -or $_.TaskPath -like "*$t*" }
    foreach($task in $tasks){
      try{ Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
           Stop-ScheduledTask    -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
           $stopped += "Task:$($task.TaskName)"
           Write-Diag ("Отключена задача: {0}" -f $task.TaskName) } catch {}
    }
  }

  $procs = Get-Process -ErrorAction SilentlyContinue
  foreach($p in $procs){
    foreach($pat in $VpnProcPatterns){
      if ($p.ProcessName -like "*$pat*"){
        try{ Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue; $stopped += "Proc:$($p.ProcessName)"
             Write-Diag ("Остановлен процесс: {0} PID={1}" -f $p.ProcessName,$p.Id) } catch {}
        break
      }
    }
  }

  $drv = Get-ChildItem "$env:WINDIR\System32\drivers" -Filter "WinDivert*.sys" -ErrorAction SilentlyContinue
  if ($drv){ Write-Diag ("Найден драйвер WinDivert: {0}" -f ($drv.Name -join ", ")) }

  if ($stopped.Count){ Write-Diag ("Итог: отключено/остановлено: {0}" -f ($stopped -join ", ")) }
  else { Write-Diag "Конфликтующие сервисы/задачи/процессы не обнаружены или уже отключены." }
}

# ── Оркестрация ────────────────────────────────────────────────────────────────
function Get-SelectedItems {
  $list = New-Object System.Collections.Generic.List[Object]
  foreach($row in $controls.dgScan.Items){ if ($row -and $row.Selected){ $list.Add($row) } }
  return $list
}
function Create-RestorePoint {
  try{ Checkpoint-Computer -Description "CiscoCleanup $(Get-Date -f yyyyMMdd_HHmmss)" -RestorePointType "MODIFY_SETTINGS"; Write-UILog "Создана точка восстановления." }
  catch{ Write-UILog ("Не удалось создать точку восстановления: {0}" -f $_.Exception.Message) "WARN" }
}
function Run-Flow([bool]$full,[bool]$svc,[bool]$folders,[bool]$reg,[bool]$backup,[bool]$force,[bool]$whatif,[bool]$html,[bool]$restore,[bool]$selectionOnly){
  $sel = if ($selectionOnly){ Get-SelectedItems } else { $null }
  Write-UILog ("Запуск: full={0} svc={1} folders={2} reg={3} backup={4} force={5} whatif={6} users={7}" -f $full,$svc,$folders,$reg,$backup,$force,$whatif,($(if($controls.rbAll.IsChecked){"ALL"}else{"CURRENT"})))
  if ($restore -and -not $whatif){ Create-RestorePoint }
  elseif ($restore -and $whatif){ Write-UILog "WHATIF: restore point creation skipped for dry run" }

  if ($full -or $svc){ Stop-CiscoProcesses $whatif $sel; Stop-CiscoServices $whatif $sel; Remove-CiscoServices $whatif $sel }
  if ($full -or $folders){ Remove-CiscoFolders $whatif $backup $force $sel }
  if ($full -or $reg)    { Remove-CiscoRegistry $whatif $backup $sel }

  if ($html){
    $p = Resolve-Env $controls.tbHtmlPath.Text
    Save-HtmlReport -Items ($controls.dgScan.ItemsSource) -Path $p
    Write-UILog ("HTML-отчёт: {0}" -f $p)
  }
  Write-UILog "Готово. Рекомендуется перезагрузка."
}

# ── Привязка UI ────────────────────────────────────────────────────────────────
$controls.btnScan.Add_Click({ $controls.tbConsole.Clear(); Do-Scan | Out-Null; Write-UILog "Сканирование завершено." })
$controls.cbOnlyFound.Add_Click({ $null = Do-Scan })
$controls.btnExportCsv.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Join-Path $global:CleanupRoot "scan.csv"; $items|Export-Csv -Path $p -NoTypeInformation -Encoding UTF8; Write-UILog ("Экспорт CSV: {0}" -f $p); Start-Process $p } })
$controls.btnExportJson.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Join-Path $global:CleanupRoot "scan.json"; $items|ConvertTo-Json -Depth 4|Set-Content -Path $p -Encoding UTF8; Write-UILog ("Экспорт JSON: {0}" -f $p); Start-Process $p } })
$controls.btnExportHtml.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Resolve-Env $controls.tbHtmlPath.Text; Save-HtmlReport -Items $items -Path $p; Write-UILog ("Экспорт HTML: {0}" -f $p); Start-Process $p } })
$controls.btnPing.Add_Click({ Invoke-PingFirstBit })
$controls.btnOpenLog.Add_Click({ $p=Resolve-Env $controls.tbLogPath.Text; if(Test-Path $p){ Start-Process $p } })
$controls.btnOpenHtml.Add_Click({ $p=Resolve-Env $controls.tbHtmlPath.Text; if(Test-Path $p){ Start-Process $p } })
$controls.btnAnalyze.Add_Click({
  $controls.tbConsole.Clear()
  Run-Flow ($controls.cbFull.IsChecked) ($controls.cbServices.IsChecked) ($controls.cbFolders.IsChecked) ($controls.cbRegistry.IsChecked) ($controls.cbBackup.IsChecked) ($controls.cbForce.IsChecked) $true ($controls.cbHtml.IsChecked) $false ($controls.cbSelectionOnly.IsChecked)
})
$controls.btnRun.Add_Click({
  $controls.tbConsole.Clear()
  $r = [System.Windows.MessageBox]::Show(
    "Are you sure? Cleanup may affect the network stack.",
    "Confirmation",
    "YesNo",
    "Warning"
  )
  if ($r -eq "Yes") {
    Run-Flow `
      ($controls.cbFull.IsChecked) `
      ($controls.cbServices.IsChecked) `
      ($controls.cbFolders.IsChecked) `
      ($controls.cbRegistry.IsChecked) `
      ($controls.cbBackup.IsChecked) `
      ($controls.cbForce.IsChecked) `
      ($controls.cbWhatIf.IsChecked) `
      ($controls.cbHtml.IsChecked) `
      ($controls.cbRestorePoint.IsChecked) `
      ($controls.cbSelectionOnly.IsChecked)
  }
})
$controls.btnClose.Add_Click({ $window.Close() })

$controls.btnDiag.Add_Click({ $controls.tbDiag.Clear(); Test-VpnDiagnostics -TargetHost "vpn.1cbit.ru" })
$controls.btnDisableAdapters.Add_Click({ Disable-SuspiciousAdapters })
$controls.btnStopGoodbye.Add_Click({ Stop-ConflictTools })

$window.ShowDialog() | Out-Null
