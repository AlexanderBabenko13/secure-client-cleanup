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
        Title="Очистка Cisco Secure Client" Height="960" Width="1360"
        MinHeight="860" MinWidth="1180" WindowStartupLocation="CenterScreen"
        Background="#0F0F0F" Foreground="#F5F5F5" FontFamily="Segoe UI">
  <Window.Resources>
    <ResourceDictionary>
      <Color x:Key="ColorBg">#0F0F0F</Color>
      <Color x:Key="ColorPanel">#181818</Color>
      <Color x:Key="ColorPanelAlt">#202020</Color>
      <Color x:Key="ColorCard">#1C1C1C</Color>
      <Color x:Key="ColorCardSoft">#242424</Color>
      <Color x:Key="ColorBorder">#3A3A3A</Color>
      <Color x:Key="ColorText">#F5F5F5</Color>
      <Color x:Key="ColorMuted">#B3B3B3</Color>
      <Color x:Key="ColorAccent">#60CDFF</Color>
      <Color x:Key="ColorSuccess">#6CCB5F</Color>
      <Color x:Key="ColorWarn">#FCE100</Color>
      <Color x:Key="ColorDanger">#FF99A4</Color>

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
      <LinearGradientBrush x:Key="BrushWindow" StartPoint="0,0" EndPoint="1,1">
        <GradientStop Color="#161616" Offset="0"/>
        <GradientStop Color="#0F0F0F" Offset="0.55"/>
        <GradientStop Color="#121820" Offset="1"/>
      </LinearGradientBrush>

      <Style TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
      </Style>

      <Style x:Key="TitleText" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="FontSize" Value="28"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
      </Style>

      <Style x:Key="SectionTitle" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="FontSize" Value="16"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Margin" Value="0,0,0,8"/>
      </Style>

      <Style x:Key="MutedText" TargetType="TextBlock">
        <Setter Property="Foreground" Value="{StaticResource BrushMuted}"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="TextWrapping" Value="Wrap"/>
      </Style>

      <Style x:Key="Card" TargetType="Border">
        <Setter Property="Background" Value="{StaticResource BrushCard}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="CornerRadius" Value="12"/>
        <Setter Property="Padding" Value="16"/>
        <Setter Property="Margin" Value="0,0,0,12"/>
      </Style>

      <Style x:Key="SoftCard" TargetType="Border" BasedOn="{StaticResource Card}">
        <Setter Property="Background" Value="{StaticResource BrushCardSoft}"/>
        <Setter Property="BorderBrush" Value="#333333"/>
        <Setter Property="CornerRadius" Value="10"/>
        <Setter Property="Padding" Value="12"/>
      </Style>

      <Style x:Key="MetricCard" TargetType="Border" BasedOn="{StaticResource SoftCard}">
        <Setter Property="Padding" Value="10,5"/>
        <Setter Property="Margin" Value="0"/>
        <Setter Property="VerticalAlignment" Value="Stretch"/>
      </Style>

      <Style TargetType="Button">
        <Setter Property="Background" Value="#2D2D2D"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="#454545"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="14,9"/>
        <Setter Property="MinHeight" Value="38"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Cursor" Value="Hand"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="Button">
              <Border Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter Property="Background" Value="#3A3A3A"/>
                  <Setter Property="BorderBrush" Value="{StaticResource BrushAccent}"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                  <Setter Property="Background" Value="#252525"/>
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
        <Setter Property="Background" Value="#60CDFF"/>
        <Setter Property="BorderBrush" Value="#60CDFF"/>
        <Setter Property="Foreground" Value="#0F0F0F"/>
      </Style>

      <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#C42B1C"/>
        <Setter Property="BorderBrush" Value="#FF99A4"/>
        <Setter Property="Foreground" Value="#FFFFFF"/>
      </Style>

      <Style x:Key="WarningButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Background" Value="#3B3211"/>
        <Setter Property="BorderBrush" Value="#D8B600"/>
        <Setter Property="Foreground" Value="#FFF4B8"/>
      </Style>

      <Style TargetType="CheckBox">
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="Margin" Value="0,1"/>
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
                <Border x:Name="Box" Width="16" Height="16" CornerRadius="4" Background="#202020"
                        BorderBrush="#707070" BorderThickness="1.2" HorizontalAlignment="Left" VerticalAlignment="Center"/>
                <Path x:Name="CheckMark" Grid.Column="0" Data="M 3 8 L 7 12 L 14 4" Stroke="#FFFFFF" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round" Visibility="Collapsed"/>
                <ContentPresenter Grid.Column="1" VerticalAlignment="Center" RecognizesAccessKey="True"/>
              </Grid>
              <ControlTemplate.Triggers>
                <Trigger Property="IsChecked" Value="True">
                  <Setter TargetName="Box" Property="Background" Value="#0078D4"/>
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
        <Setter Property="Margin" Value="0,1"/>
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
                <Ellipse x:Name="Ring" Width="16" Height="16" Stroke="#707070" StrokeThickness="1.3" Fill="#202020"
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
        <Setter Property="Background" Value="#202020"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Padding" Value="8"/>
        <Setter Property="CaretBrush" Value="{StaticResource BrushAccent}"/>
      </Style>

      <Style x:Key="ConsoleTextBox" TargetType="TextBox" BasedOn="{StaticResource {x:Type TextBox}}">
        <Setter Property="Background" Value="#050A14"/>
        <Setter Property="Foreground" Value="#E5F4FF"/>
        <Setter Property="BorderBrush" Value="#2A3A55"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="FontFamily" Value="Consolas"/>
        <Setter Property="FontSize" Value="14"/>
        <Setter Property="Padding" Value="10"/>
        <Setter Property="MinHeight" Value="140"/>
      </Style>

      <Style TargetType="TabControl">
        <Setter Property="Background" Value="#050A14"/>
        <Setter Property="BorderBrush" Value="#2A3A55"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="TabControl">
              <Grid KeyboardNavigation.TabNavigation="Local">
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TabPanel Grid.Row="0" IsItemsHost="True" Background="#171C26" KeyboardNavigation.TabIndex="1"/>
                <Border Grid.Row="1" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                        BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="0,0,8,8">
                  <ContentPresenter x:Name="PART_SelectedContentHost" ContentSource="SelectedContent" Margin="0"/>
                </Border>
              </Grid>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style TargetType="TabItem">
        <Setter Property="Foreground" Value="#C8D3E0"/>
        <Setter Property="Background" Value="#242A34"/>
        <Setter Property="BorderBrush" Value="#39465A"/>
        <Setter Property="Padding" Value="18,9"/>
        <Setter Property="MinHeight" Value="38"/>
        <Setter Property="FontWeight" Value="SemiBold"/>
        <Setter Property="Template">
          <Setter.Value>
            <ControlTemplate TargetType="TabItem">
              <Border x:Name="TabBorder" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="1,1,1,0" CornerRadius="8,8,0,0" Margin="0,0,4,0"
                      Padding="{TemplateBinding Padding}" MinHeight="{TemplateBinding MinHeight}">
                <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property="IsSelected" Value="True">
                  <Setter Property="Foreground" Value="#E5F4FF"/>
                  <Setter TargetName="TabBorder" Property="Background" Value="#10253F"/>
                  <Setter TargetName="TabBorder" Property="BorderBrush" Value="#60CDFF"/>
                  <Setter TargetName="TabBorder" Property="BorderThickness" Value="1,1,1,3"/>
                </Trigger>
                <Trigger Property="IsMouseOver" Value="True">
                  <Setter TargetName="TabBorder" Property="Background" Value="#2D3541"/>
                  <Setter Property="Foreground" Value="#FFFFFF"/>
                </Trigger>
                <Trigger Property="IsEnabled" Value="False">
                  <Setter Property="Opacity" Value="0.45"/>
                </Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
          </Setter.Value>
        </Setter>
      </Style>

      <Style x:Key="CompactButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="MinHeight" Value="30"/>
        <Setter Property="Padding" Value="10,5"/>
        <Setter Property="FontSize" Value="12"/>
      </Style>

      <Style x:Key="ActionButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
        <Setter Property="Padding" Value="8,7"/>
        <Setter Property="FontSize" Value="12"/>
      </Style>

      <Style TargetType="DataGrid">
        <Setter Property="Background" Value="#181818"/>
        <Setter Property="Foreground" Value="{StaticResource BrushText}"/>
        <Setter Property="FontSize" Value="12"/>
        <Setter Property="RowHeight" Value="34"/>
        <Setter Property="BorderBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="BorderThickness" Value="1"/>
        <Setter Property="RowBackground" Value="#1C1C1C"/>
        <Setter Property="AlternatingRowBackground" Value="#222222"/>
        <Setter Property="GridLinesVisibility" Value="Horizontal"/>
        <Setter Property="HorizontalGridLinesBrush" Value="{StaticResource BrushBorder}"/>
        <Setter Property="VerticalGridLinesBrush" Value="{StaticResource BrushBorder}"/>
      </Style>

      <Style TargetType="DataGridColumnHeader">
        <Setter Property="Background" Value="#292929"/>
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
        <Setter Property="Height" Value="4"/>
        <Setter Property="Background" Value="#25303B"/>
        <Setter Property="Foreground" Value="{StaticResource BrushAccent}"/>
        <Setter Property="BorderThickness" Value="0"/>
      </Style>

    </ResourceDictionary>
  </Window.Resources>

  <Grid Background="{StaticResource BrushWindow}">
    <Grid.ColumnDefinitions>
      <ColumnDefinition Width="220"/>
      <ColumnDefinition Width="*"/>
      <ColumnDefinition Width="280"/>
    </Grid.ColumnDefinitions>

    <Border Grid.Column="0" Background="#D9181818" BorderBrush="{StaticResource BrushBorder}" BorderThickness="0,0,1,0" Padding="18">
      <Grid>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="*"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel>
          <Border Width="56" Height="56" CornerRadius="12" Background="#20303A" BorderBrush="{StaticResource BrushAccent}" BorderThickness="1" HorizontalAlignment="Left" Margin="0,0,0,14">
            <TextBlock Text="SC" FontSize="20" FontWeight="Bold" Foreground="{StaticResource BrushAccent}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <TextBlock Text="Cisco Secure Client" FontSize="19" FontWeight="SemiBold"/>
          <TextBlock Text="Утилита очистки" Style="{StaticResource MutedText}" Margin="0,2,0,18"/>
          <Border Style="{StaticResource SoftCard}" BorderBrush="#496675">
            <StackPanel>
              <TextBlock Text="Безопасная очистка" FontWeight="SemiBold"/>
              <TextBlock Text="Сначала выполните сканирование и пробный запуск." Style="{StaticResource MutedText}" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </StackPanel>
        <StackPanel Grid.Row="1" Margin="0,12,0,0">
          <TextBlock Text="ПОРЯДОК РАБОТЫ" Style="{StaticResource MutedText}" Margin="0,0,0,8"/>
          <TextBlock Text="1. Сканирование" Margin="0,4"/>
          <TextBlock Text="2. Пробный запуск" Margin="0,4"/>
          <TextBlock Text="3. Резервная копия" Margin="0,4"/>
          <TextBlock Text="4. Очистка" Margin="0,4"/>
          <TextBlock Text="5. Перезагрузка" Margin="0,4"/>
          <TextBlock Text="6. Переустановка Cisco Secure Client" Margin="0,4"/>
        </StackPanel>
        <StackPanel Grid.Row="2">
          <Border CornerRadius="8" Background="#18351C" BorderBrush="#397D42" BorderThickness="1" Padding="10" Margin="0,0,0,10">
            <StackPanel>
              <TextBlock Text="Система готова" Foreground="{StaticResource BrushSuccess}" FontWeight="SemiBold"/>
              <TextBlock Text="Безопасные параметры активны" Style="{StaticResource MutedText}" Margin="0,3,0,0"/>
            </StackPanel>
          </Border>
          <TextBlock Text="Локальная сборка PowerShell 5.1" Style="{StaticResource MutedText}"/>
        </StackPanel>
      </Grid>
    </Border>

    <Grid Grid.Column="1" Margin="16">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="128"/>
        <RowDefinition Height="185"/>
        <RowDefinition Height="142"/>
        <RowDefinition Height="1.6*" MinHeight="150"/>
        <RowDefinition Height="1*" MinHeight="210" MaxHeight="250"/>
      </Grid.RowDefinitions>

      <Grid Margin="0,0,0,10">
        <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock Text="Очистка Cisco Secure Client" Style="{StaticResource TitleText}"/>
          <TextBlock Text="Безопасная подготовка ПК к переустановке Cisco AnyConnect / Secure Client" Style="{StaticResource MutedText}" Margin="0,4,0,0"/>
        </StackPanel>
        <Button x:Name="btnClose" Grid.Column="1" Content="Закрыть" Width="86" VerticalAlignment="Center"/>
      </Grid>

      <Grid Grid.Row="1" Margin="0,0,0,10">
        <Grid.ColumnDefinitions><ColumnDefinition Width="1.7*"/><ColumnDefinition Width="1*"/></Grid.ColumnDefinitions>
        <Border Style="{StaticResource Card}" Margin="0,0,10,0" BorderBrush="#397D42" Padding="12">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <StackPanel>
              <TextBlock Text="Безопасные действия" FontWeight="SemiBold" Foreground="{StaticResource BrushSuccess}"/>
              <TextBlock Text="Не удаляют данные и используются для проверки состояния системы." Style="{StaticResource MutedText}"/>
            </StackPanel>
            <UniformGrid Grid.Row="1" Columns="5" Margin="0,10,0,0" VerticalAlignment="Center">
              <Button x:Name="btnScan" Content="Сканировать" Style="{StaticResource AccentButton}" Height="42" Padding="8,7" Margin="0,0,6,0"/>
              <Button x:Name="btnAnalyze" Content="Пробный запуск" Style="{StaticResource ActionButton}" Height="42" Margin="0,0,6,0"/>
              <Button x:Name="btnDiag" Content="Диагностика" Style="{StaticResource ActionButton}" Height="42" Margin="0,0,6,0"/>
              <Button x:Name="btnPing" Content="Проверить VPN" Style="{StaticResource ActionButton}" Height="42" Margin="0,0,6,0" ToolTip="Проверить доступ к vpn.1cbit.ru"/>
              <Button x:Name="btnDisableAdapters" Content="Показать адаптеры" Style="{StaticResource ActionButton}" Height="42" Padding="6,7" FontSize="11" ToolTip="Показать подозрительные адаптеры без изменения системы"/>
            </UniformGrid>
          </Grid>
        </Border>
        <Border Grid.Column="1" Style="{StaticResource Card}" BorderBrush="#8C6D1F" Padding="12" Margin="0">
          <Grid>
            <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
            <StackPanel>
              <TextBlock Text="Действия, изменяющие систему" FontWeight="SemiBold" Foreground="#FFF4B8"/>
              <TextBlock Text="Используйте только после анализа результатов." Style="{StaticResource MutedText}"/>
            </StackPanel>
            <UniformGrid Grid.Row="1" Columns="2" Margin="0,10,0,0" VerticalAlignment="Center">
              <Button x:Name="btnRun" Content="Очистить" Style="{StaticResource DangerButton}" Height="42" Padding="8,7" Margin="0,0,6,0"/>
              <Button x:Name="btnStopGoodbye" Content="Остановить DPI / WinDivert" ToolTip="Остановить GoodbyeDPI / WinDivert" Style="{StaticResource WarningButton}" Height="42" Padding="6,7" FontSize="11"/>
            </UniformGrid>
          </Grid>
        </Border>
      </Grid>

      <Border Grid.Row="2" Style="{StaticResource Card}" Padding="12" Margin="0,0,0,10">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid Grid.Row="0">
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <StackPanel>
              <TextBlock Text="Параметры очистки" Style="{StaticResource SectionTitle}"/>
              <TextBlock Text="Пробный запуск ничего не удаляет и рекомендуется перед очисткой." Foreground="{StaticResource BrushAccent}" FontSize="12"/>
            </StackPanel>
            <ProgressBar x:Name="pb" Grid.Column="1" Width="160" Minimum="0" Maximum="100"
                         VerticalAlignment="Center" Visibility="Collapsed"
                         ToolTip="Идёт сканирование..."/>
          </Grid>
          <Grid Grid.Row="1" Margin="0,8,0,0">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="1*"/>
              <ColumnDefinition Width="1.2*"/>
              <ColumnDefinition Width="1.2*"/>
            </Grid.ColumnDefinitions>
            <StackPanel>
              <CheckBox x:Name="cbWhatIf" Content="Пробный запуск" IsChecked="True" Foreground="{StaticResource BrushAccent}" FontWeight="SemiBold"/>
              <CheckBox x:Name="cbFull" Content="Полная очистка"/>
              <CheckBox x:Name="cbServices" Content="Службы и процессы"/>
              <CheckBox x:Name="cbFolders" Content="Папки и AppData"/>
              <CheckBox x:Name="cbRegistry" Content="Реестр"/>
            </StackPanel>
            <StackPanel Grid.Column="1" Margin="16,0,0,0">
              <RadioButton x:Name="rbCurrent" Content="Только текущий пользователь" IsChecked="True"/>
              <RadioButton x:Name="rbAll" Content="Все профили пользователей"/>
              <CheckBox x:Name="cbBackup" Content="Резервная копия реестра и папок"/>
              <CheckBox x:Name="cbHtml" Content="Создать HTML-отчёт" IsChecked="True"/>
            </StackPanel>
            <StackPanel Grid.Column="2" Margin="16,0,0,0">
              <CheckBox x:Name="cbForce" Content="Принудительный повтор"/>
              <CheckBox x:Name="cbRestorePoint" Content="Создать точку восстановления"/>
              <CheckBox x:Name="cbSelectionOnly" Content="Только выбранные строки"/>
              <CheckBox x:Name="cbOnlyFound" Content="Показывать только найденное"/>
            </StackPanel>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="3" Style="{StaticResource Card}" Padding="8" Margin="0,0,0,10">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock Text="Найденные компоненты" Style="{StaticResource SectionTitle}" Margin="4,0,0,6"/>
          <Grid Grid.Row="1">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/><ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions><RowDefinition Height="*"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Border Style="{StaticResource MetricCard}" Margin="0,0,6,4"><StackPanel VerticalAlignment="Center"><TextBlock Text="Службы" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblServicesCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Column="1" Style="{StaticResource MetricCard}" Margin="0,0,6,4"><StackPanel VerticalAlignment="Center"><TextBlock Text="Процессы" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblProcessesCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Column="2" Style="{StaticResource MetricCard}" Margin="0,0,6,4"><StackPanel VerticalAlignment="Center"><TextBlock Text="Папки" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblFoldersCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Column="3" Style="{StaticResource MetricCard}" Margin="0,0,0,4"><StackPanel VerticalAlignment="Center"><TextBlock Text="Реестр" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblRegistryCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Row="1" Style="{StaticResource MetricCard}" Margin="0,0,6,0"><StackPanel VerticalAlignment="Center"><TextBlock Text="AppData" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblAppDataCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Row="1" Grid.Column="1" Style="{StaticResource MetricCard}" Margin="0,0,6,0"><StackPanel VerticalAlignment="Center"><TextBlock Text="Установленные программы" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblProgramsCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Row="1" Grid.Column="2" Style="{StaticResource MetricCard}" Margin="0,0,6,0"><StackPanel VerticalAlignment="Center"><TextBlock Text="Защищённые пути" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblProtectedCount" Text="После scan" FontSize="11" FontWeight="SemiBold"/></StackPanel></Border>
          <Border Grid.Row="1" Grid.Column="3" Background="#20303A" BorderBrush="{StaticResource BrushAccent}" BorderThickness="1" CornerRadius="10" Padding="10,5"><StackPanel VerticalAlignment="Center"><TextBlock Text="Итого элементов" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblTotalCount" Text="После scan" FontSize="11" Foreground="{StaticResource BrushAccent}" FontWeight="SemiBold"/></StackPanel></Border>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="4" Style="{StaticResource Card}" Padding="10" Margin="0,0,0,10">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="220"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock Text="Результаты сканирования" Style="{StaticResource SectionTitle}"/>
            <TextBox x:Name="tbScanSearch" Grid.Column="1" Height="30" Margin="8,0,10,0" Padding="8,4"
                     VerticalContentAlignment="Center" ToolTip="Поиск по категории, объекту, состоянию и подробностям"/>
            <StackPanel Grid.Column="2" Orientation="Horizontal">
              <Button x:Name="btnScanResults" Content="Сканировать" Style="{StaticResource CompactButton}" BorderBrush="{StaticResource BrushAccent}" Margin="0,0,6,0"/>
              <Button x:Name="btnExportCsv" Content="CSV" Style="{StaticResource CompactButton}" Margin="0,0,6,0"/>
              <Button x:Name="btnExportJson" Content="JSON" Style="{StaticResource CompactButton}" Margin="0,0,6,0"/>
              <Button x:Name="btnExportHtml" Content="HTML" Style="{StaticResource CompactButton}"/>
            </StackPanel>
          </Grid>
          <Grid Grid.Row="1" Margin="0,8,0,0">
          <DataGrid x:Name="dgScan" AutoGenerateColumns="False" CanUserAddRows="False"
                    HeadersVisibility="Column" SelectionMode="Extended" SelectionUnit="FullRow"
                    VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
                    ScrollViewer.CanContentScroll="True">
            <DataGrid.Columns>
              <DataGridCheckBoxColumn Header="Выбор" Binding="{Binding Selected}" Width="64"/>
              <DataGridTextColumn Header="Категория" Binding="{Binding DisplayCategory}" Width="120"/>
              <DataGridTextColumn Header="Объект" Binding="{Binding Name}" Width="220"/>
              <DataGridTextColumn Header="Состояние" Binding="{Binding DisplayState}" Width="140"/>
              <DataGridTextColumn Header="Подробности" Binding="{Binding DisplayDetails}" Width="230"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border x:Name="scanEmptyPanel" Background="#E6171717" IsHitTestVisible="False" Margin="0,34,0,0">
            <StackPanel HorizontalAlignment="Center" VerticalAlignment="Center">
              <TextBlock x:Name="scanEmptyTitle" Text="Сканирование ещё не проводилось." FontSize="15" FontWeight="SemiBold" HorizontalAlignment="Center"/>
              <TextBlock x:Name="scanEmptyHint" Text="Нажмите «Сканировать» для получения результатов." Style="{StaticResource MutedText}" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
          </Grid>
        </Grid>
      </Border>

      <Border Grid.Row="5" Style="{StaticResource Card}" Padding="10" BorderBrush="#2A3A55">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
            <TextBlock Text="Журналы и диагностика" Style="{StaticResource SectionTitle}"/>
            <StackPanel Grid.Column="1" Orientation="Horizontal">
              <Button x:Name="btnClearLog" Content="Очистить журнал" Style="{StaticResource CompactButton}" Margin="0,0,6,0"/>
              <Button x:Name="btnClearDiag" Content="Очистить диагностику" Style="{StaticResource CompactButton}" Margin="0,0,6,0"/>
              <Button x:Name="btnCopyDiag" Content="Копировать диагностику" Style="{StaticResource CompactButton}"/>
            </StackPanel>
          </Grid>
          <TabControl x:Name="tabOutput" Grid.Row="1" Margin="0,6,0,0">
            <TabItem Header="Журнал действий">
              <TextBox x:Name="tbConsole" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" Style="{StaticResource ConsoleTextBox}" IsReadOnly="True"/>
            </TabItem>
            <TabItem x:Name="tabDiagnostics" Header="Вывод диагностики">
              <TextBox x:Name="tbDiag" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto" TextWrapping="NoWrap" Style="{StaticResource ConsoleTextBox}" IsReadOnly="True"/>
            </TabItem>
          </TabControl>
        </Grid>
      </Border>
    </Grid>

    <Border Grid.Column="2" Background="{StaticResource BrushPanel}" BorderBrush="{StaticResource BrushBorder}" BorderThickness="1,0,0,0" Padding="14">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
        <TextBlock Text="Сводка" FontSize="20" FontWeight="SemiBold" Margin="0,0,0,10"/>
        <StackPanel Grid.Row="1">
          <Border Style="{StaticResource SoftCard}"><StackPanel><TextBlock Text="Найденные элементы" Style="{StaticResource MutedText}"/><TextBlock x:Name="lblSummary" Text="Сканирование ещё не запускалось" FontWeight="SemiBold" TextWrapping="Wrap" Margin="0,4,0,0"/></StackPanel></Border>
          <Border Style="{StaticResource SoftCard}"><StackPanel><TextBlock Text="Защищённые корневые пути" Style="{StaticResource MutedText}"/><TextBlock Text="Реестр и папки защищены" Foreground="{StaticResource BrushSuccess}" FontWeight="SemiBold" Margin="0,4,0,0"/></StackPanel></Border>
          <Border Style="{StaticResource SoftCard}">
            <StackPanel>
              <TextBlock Text="Путь к журналу" FontWeight="SemiBold"/>
              <TextBox x:Name="tbLogPath" Text="%ProgramData%\CiscoCleanup\cleanup.log" Height="44" Margin="0,7,0,6" Padding="7,5" TextWrapping="Wrap" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Disabled" FontSize="10" ToolTip="%ProgramData%\CiscoCleanup\cleanup.log"/>
              <Button x:Name="btnOpenLog" Content="Открыть" Style="{StaticResource CompactButton}"/>
            </StackPanel>
          </Border>
          <Border Style="{StaticResource SoftCard}">
            <StackPanel>
              <TextBlock Text="Путь к HTML-отчёту" FontWeight="SemiBold"/>
              <TextBox x:Name="tbHtmlPath" Text="%ProgramData%\CiscoCleanup\report.html" Height="44" Margin="0,7,0,6" Padding="7,5" TextWrapping="Wrap" HorizontalScrollBarVisibility="Disabled" VerticalScrollBarVisibility="Disabled" FontSize="10" ToolTip="%ProgramData%\CiscoCleanup\report.html"/>
              <Button x:Name="btnOpenHtml" Content="Открыть" Style="{StaticResource CompactButton}"/>
            </StackPanel>
          </Border>
        </StackPanel>
        <Border Grid.Row="2" Style="{StaticResource SoftCard}" Margin="0">
          <StackPanel>
            <TextBlock Text="Текущий план" FontWeight="SemiBold" Margin="0,0,0,6"/>
            <TextBlock Text="Сканирование → Пробный запуск → Резервная копия → Очистка → Перезагрузка" Style="{StaticResource MutedText}"/>
          </StackPanel>
        </Border>
      </Grid>
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
  if (-not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { New-Item -ItemType File -Force -Path $LogPath | Out-Null }
}
function Write-UILog([string]$Message,[string]$Level="INFO"){
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts][$Level] $Message"
  if ($controls.tbConsole){ $controls.tbConsole.AppendText($line + [Environment]::NewLine); $controls.tbConsole.ScrollToEnd() }
  $logPath = Resolve-Env $controls.tbLogPath.Text; Ensure-LogPath $logPath; Add-Content -Path $logPath -Value $line
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
  "Cisco Secure Client",
  "Cisco Secure Client\VPN",
  "Cisco Secure Client\ISE Posture",
  "Cisco Secure Client\Diagnostics and Reporting Tool",
  "Cisco Secure Client\Umbrella",
  "Cisco Secure Client\Network Access Manager"
)
$ProgramFolders = @(
  $programRoots = @($env:ProgramFiles, $ProgramFilesX86) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    Sort-Object -Unique

  foreach($root in $programRoots) {
    $ciscoRoot = Join-Path $root "Cisco"
    foreach($name in $ProgramFolderNames) {
      Join-Path $ciscoRoot $name
    }
  }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

$ProtectedScanFolders = @(
  if ($env:ProgramFiles) { Join-Path $env:ProgramFiles "Cisco" }
  if ($ProgramFilesX86) { Join-Path $ProgramFilesX86 "Cisco" }
  if ($env:ProgramData) { Join-Path $env:ProgramData "Cisco" }
  if ($env:ProgramData) { Join-Path $env:ProgramData "Cisco Systems" }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique

$UninstallRegistryPaths = @(
  "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
  "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

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
    if ($p -and (Test-Path -LiteralPath $p -PathType Container)) {
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
function Get-CiscoInstallCandidates {
  param(
    [string[]]$KnownProgramFolders,
    [string[]]$ProtectedFolders,
    [string[]]$UninstallRegistryPaths,
    [string[]]$ServiceNames,
    [string[]]$ProcessNames,
    [bool]$AllUsers
  )

  $candidateMap = @{}
  $programCandidates = New-Object System.Collections.Generic.List[Object]
  $namePatterns = @(
    "*Cisco AnyConnect*", "*Cisco Secure Client*", "*AnyConnect*", "*Secure Client*",
    "*VPN*", "*ISE Posture*", "*Diagnostics and Reporting Tool*", "*Umbrella*", "*Network Access Manager*"
  )

  function Normalize-DiscoveryPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    return ([Environment]::ExpandEnvironmentVariables($Path).Trim().Trim('"').TrimEnd('\')).ToLowerInvariant()
  }

  function Test-DiscoveryName([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    foreach ($pattern in $namePatterns) {
      if ($Name -like $pattern) { return $true }
    }
    return $false
  }

  function Test-ProtectedDiscoveryPath([string]$Path) {
    $normalized = Normalize-DiscoveryPath $Path
    foreach ($protectedPath in $ProtectedFolders) {
      if ($normalized -eq (Normalize-DiscoveryPath $protectedPath)) { return $true }
    }
    return $false
  }

  function Test-RemovableDiscoveryPath([string]$Path) {
    $normalized = Normalize-DiscoveryPath $Path
    if ([string]::IsNullOrWhiteSpace($normalized) -or (Test-ProtectedDiscoveryPath $Path)) { return $false }
    $programDataNormalized = Normalize-DiscoveryPath $env:ProgramData
    if ($programDataNormalized -and $normalized.StartsWith($programDataNormalized + '\')) { return $false }
    foreach ($knownPath in $KnownProgramFolders) {
      if ($normalized -eq (Normalize-DiscoveryPath $knownPath)) { return $true }
    }
    foreach ($protectedPath in $ProtectedFolders) {
      $protectedNormalized = Normalize-DiscoveryPath $protectedPath
      if ($normalized.StartsWith($protectedNormalized + '\') -and (Test-DiscoveryName ([System.IO.Path]::GetFileName($Path)))) {
        return $true
      }
    }
    return $false
  }

  function Get-ExecutablePathFromCommandLine([string]$ImagePath) {
    if ([string]::IsNullOrWhiteSpace($ImagePath)) { return $null }
    $expanded = [Environment]::ExpandEnvironmentVariables($ImagePath).Trim()
    if ($expanded -match '^\s*"([^"]+?\.exe)"') { return $matches[1] }
    if ($expanded -match '^\s*([^\r\n]+?\.exe)(?:\s|$)') { return $matches[1].Trim() }
    return $expanded.Trim('"')
  }

  function Add-FolderCandidate {
    param(
      [string]$Path,
      [string]$Source,
      [string]$Confidence = "Medium",
      [string]$ExtraDetails = "",
      [bool]$IncludeMissing = $false,
      [bool]$ForceProtected = $false,
      [Nullable[bool]]$ForceRemovable = $null
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $expandedPath = [Environment]::ExpandEnvironmentVariables($Path).Trim().Trim('"').TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($expandedPath)) { return }
    $exists = Test-Path -LiteralPath $expandedPath -PathType Container
    if (-not $exists -and -not $IncludeMissing) { return }

    $isProtected = $ForceProtected -or (Test-ProtectedDiscoveryPath $expandedPath)
    $isRemovable = if ($null -ne $ForceRemovable) { [bool]$ForceRemovable } else { Test-RemovableDiscoveryPath $expandedPath }
    if ($isProtected) { $isRemovable = $false }

    $key = "folder|" + (Normalize-DiscoveryPath $expandedPath)
    if (-not $candidateMap.ContainsKey($key)) {
      $candidateMap[$key] = [PSCustomObject]@{
        Category = $(if ($isProtected) { "Protected Folder" } else { "Folder" })
        Name = $expandedPath
        State = $(if ($isProtected -and $exists) { "Protected" } elseif ($exists) { "Exists" } else { "Not found" })
        DetailsList = New-Object System.Collections.Generic.List[string]
        Path = $expandedPath
        Sources = New-Object System.Collections.Generic.List[string]
        Confidence = $Confidence
        IsProtected = [bool]$isProtected
        IsRemovable = [bool]$isRemovable
      }
    }

    $candidate = $candidateMap[$key]
    if ($candidate.Sources -notcontains $Source) { $candidate.Sources.Add($Source) }
    if ($ExtraDetails -and $candidate.DetailsList -notcontains $ExtraDetails) { $candidate.DetailsList.Add($ExtraDetails) }
    if ($candidate.Sources.Count -gt 1 -or $Confidence -eq "High") { $candidate.Confidence = "High" }
    if ($isProtected) {
      $candidate.Category = "Protected Folder"
      $candidate.State = $(if ($exists) { "Protected" } else { "Not found" })
      $candidate.IsProtected = $true
      $candidate.IsRemovable = $false
    } elseif ($isRemovable) {
      $candidate.IsRemovable = $true
    }
  }

  foreach ($knownPath in $KnownProgramFolders) {
    Add-FolderCandidate -Path $knownPath -Source "KnownPath" -Confidence "High" -IncludeMissing $true -ForceRemovable $true
  }

  foreach ($root in $ProtectedFolders) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    Add-FolderCandidate -Path $root -Source "ProtectedRoot" -Confidence "High" -ForceProtected $true `
      -ExtraDetails "ManualOnly; HighRisk; корневой путь исключён из автоматического удаления"
    Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | ForEach-Object {
      $programDataRoot = Normalize-DiscoveryPath $env:ProgramData
      $isProgramData = $programDataRoot -and (Normalize-DiscoveryPath $root).StartsWith($programDataRoot)
      if ((Test-DiscoveryName $_.Name) -or $isProgramData) {
        Add-FolderCandidate -Path $_.FullName -Source $(if ($isProgramData) { "ProgramDataChild" } else { "ProgramFilesRoot" }) `
          -Confidence "Medium" -ForceRemovable (-not $isProgramData) `
          -ExtraDetails $(if ($isProgramData) { "ManualOnly; дочерняя папка ProgramData" } else { "Обнаружена в корне Cisco" })
      }
    }
  }

  foreach ($uninstallPath in $UninstallRegistryPaths) {
    Get-ItemProperty -Path $uninstallPath -ErrorAction SilentlyContinue |
      Where-Object {
        $_.DisplayName -and ($_.DisplayName -like "*Cisco*" -or $_.DisplayName -like "*AnyConnect*" -or $_.DisplayName -like "*Secure Client*")
      } |
      ForEach-Object {
        $details = New-Object System.Collections.Generic.List[string]
        if ($_.DisplayVersion) { $details.Add(("Версия: {0}" -f $_.DisplayVersion)) }
        if ($_.Publisher) { $details.Add(("Издатель: {0}" -f $_.Publisher)) }
        if ($_.InstallLocation) { $details.Add(("Путь: {0}" -f $_.InstallLocation)) }
        if ($_.UninstallString) { $details.Add(("Удаление: {0}" -f $_.UninstallString)) }
        $programCandidates.Add([PSCustomObject]@{
          Category = "Installed Program"; Name = [string]$_.DisplayName; State = "Installed"
          Details = ($details -join "; "); Path = [string]$_.InstallLocation; Source = "UninstallRegistry"
          Confidence = "High"; IsProtected = $true; IsRemovable = $false; RegistryPath = [string]$_.PSPath
        })
        if ($_.InstallLocation) {
          Add-FolderCandidate -Path ([string]$_.InstallLocation) -Source "UninstallInstallLocation" -Confidence "High" `
            -ExtraDetails ("Программа: {0}" -f $_.DisplayName)
        }
      }
  }

  foreach ($serviceName in $ServiceNames) {
    $serviceData = Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName" -ErrorAction SilentlyContinue
    $executablePath = Get-ExecutablePathFromCommandLine ([string]$serviceData.ImagePath)
    if ($executablePath) {
      Add-FolderCandidate -Path ([System.IO.Path]::GetDirectoryName($executablePath)) -Source "ServiceImagePath" -Confidence "High" `
        -ExtraDetails ("Служба {0}; ImagePath: {1}" -f $serviceName, $serviceData.ImagePath)
    }
  }

  foreach ($processPattern in (@($ProcessNames + @("cisco*")) | Sort-Object -Unique)) {
    Get-Process -Name $processPattern -ErrorAction SilentlyContinue | ForEach-Object {
      $ProcessPath = $null
      try { $ProcessPath = [string]$_.Path } catch {}
      if ($ProcessPath) {
        Add-FolderCandidate -Path ([System.IO.Path]::GetDirectoryName($ProcessPath)) -Source "ProcessPath" -Confidence "High" `
          -ExtraDetails ("Процесс {0}; ProcessPath: {1}" -f $_.ProcessName, $ProcessPath)
      }
    }
  }

  $appDataPaths = New-Object System.Collections.Generic.List[string]
  if ($AllUsers) {
    foreach ($profile in @(Get-UserProfiles)) {
      if (-not $profile) { continue }
      $appDataPaths.Add([System.IO.Path]::Combine([string]$profile, "AppData", "Roaming", "Cisco"))
      $appDataPaths.Add([System.IO.Path]::Combine([string]$profile, "AppData", "Local", "Cisco"))
    }
  } else {
    if ($env:APPDATA) { $appDataPaths.Add((Join-Path $env:APPDATA "Cisco")) }
    if ($env:LOCALAPPDATA) { $appDataPaths.Add((Join-Path $env:LOCALAPPDATA "Cisco")) }
  }
  foreach ($appDataPath in ($appDataPaths | Sort-Object -Unique)) {
    Add-FolderCandidate -Path $appDataPath -Source "AppData" -Confidence "Medium" -IncludeMissing $true -ForceRemovable $true
  }

  $result = New-Object System.Collections.Generic.List[Object]
  foreach ($candidate in $candidateMap.Values) {
    $sources = @($candidate.Sources | Sort-Object -Unique)
    $details = @($candidate.DetailsList) + @("Sources: $($sources -join ', ')")
    $result.Add([PSCustomObject]@{
      Category = $candidate.Category; Name = $candidate.Name; State = $candidate.State
      Details = ($details -join "; "); Path = $candidate.Path; Source = ($sources -join ", ")
      Confidence = $candidate.Confidence; IsProtected = [bool]$candidate.IsProtected; IsRemovable = [bool]$candidate.IsRemovable
    })
  }
  foreach ($program in ($programCandidates | Sort-Object Name, RegistryPath -Unique)) { $result.Add($program) }
  return $result.ToArray()
}

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
if (-not ("ScanBackgroundWorkerHost" -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.ComponentModel;
using System.Linq;
using System.Management.Automation;

public static class ScanBackgroundWorkerHost
{
    public static void Run(object sender, DoWorkEventArgs e)
    {
        IDictionary input = (IDictionary)e.Argument;
        using (PowerShell powerShell = PowerShell.Create())
        {
            powerShell
                .AddScript((string)input["Script"])
                .AddParameter("Services", input["Services"])
                .AddParameter("Processes", input["Processes"])
                .AddParameter("RegistryKeys", input["RegistryKeys"])
                .AddParameter("ProgramFolders", input["ProgramFolders"])
                .AddParameter("ProtectedFolders", input["ProtectedFolders"])
                .AddParameter("UninstallRegistryPaths", input["UninstallRegistryPaths"])
                .AddParameter("AllUsers", input["AllUsers"]);

            var output = powerShell.Invoke();
            e.Result = output.ToArray();
        }
    }
}
'@
}

function Get-ScanItems {
  param(
    [string[]]$Services,
    [string[]]$Processes,
    [string[]]$RegistryKeys,
    [string[]]$ProgramFolders,
    [string[]]$ProtectedFolders,
    [string[]]$UninstallRegistryPaths,
    [bool]$AllUsers
  )

  $raw = New-Object System.Collections.Generic.List[Object]

  foreach ($s in $Services) {
    $srv = Get-Service -Name $s -ErrorAction SilentlyContinue
    if ($srv) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Service";Name=$s;State=$srv.Status;Details="StartupType=$($srv.StartType)";Path="";Source="Service";Confidence="High";IsProtected=$false;IsRemovable=$true}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Service";Name=$s;State="Not found";Details="";Path="";Source="Service";Confidence="Medium";IsProtected=$false;IsRemovable=$true}) }
  }

  foreach ($p in $Processes) {
    $procs = Get-Process -Name $p -ErrorAction SilentlyContinue
    if ($procs) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Process";Name=$p;State="Running x$($procs.Count)";Details=($procs|%{"PID="+$_.Id})-join ", ";Path="";Source="Process";Confidence="High";IsProtected=$false;IsRemovable=$true}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Process";Name=$p;State="Not running";Details="";Path="";Source="Process";Confidence="Medium";IsProtected=$false;IsRemovable=$true}) }
  }

  foreach ($candidate in @(Get-CiscoInstallCandidates `
    -KnownProgramFolders $ProgramFolders `
    -ProtectedFolders $ProtectedFolders `
    -UninstallRegistryPaths $UninstallRegistryPaths `
    -ServiceNames $Services `
    -ProcessNames $Processes `
    -AllUsers $AllUsers)) {
    $candidate | Add-Member -NotePropertyName Selected -NotePropertyValue $false -Force
    $raw.Add($candidate)
  }

  foreach ($rk in $RegistryKeys) {
    if (Test-Path $rk) { $raw.Add([PSCustomObject]@{Selected=$false;Category="Registry";Name=$rk;State="Exists";Details="";Path=$rk;Source="ServiceRegistry";Confidence="High";IsProtected=$false;IsRemovable=$true}) }
    else { $raw.Add([PSCustomObject]@{Selected=$false;Category="Registry";Name=$rk;State="Not found";Details="";Path=$rk;Source="ServiceRegistry";Confidence="Medium";IsProtected=$false;IsRemovable=$true}) }
  }

  return $raw.ToArray()
}

function Apply-ScanItems {
  param(
    [object[]]$RawItems,
    [bool]$OnlyFound
  )

  $raw = @($RawItems)
  foreach ($item in $raw) {
    $displayCategory = switch ([string]$item.Category) {
      "Service" { "Служба" }
      "Process" { "Процесс" }
      "Folder" { "Папка" }
      "Protected Folder" { "Защищённая папка" }
      "Registry" { "Реестр" }
      "Installed Program" { "Установленная программа" }
      default { [string]$item.Category }
    }

    $state = [string]$item.State
    $displayState = switch -Regex ($state) {
      "^Not found$" { "Не найдено"; break }
      "^Not running$" { "Не запущено"; break }
      "^Running x(\d+)$" { "Запущено: $($Matches[1])"; break }
      "^Running$" { "Запущено"; break }
      "^Stopped$" { "Остановлено"; break }
      "^Protected$" { "Защищено"; break }
      "^Ready$" { "Готово"; break }
      "^Exists$" { "Найдено"; break }
      "^Found$" { "Найдено"; break }
      "^Installed$" { "Установлено"; break }
      "^Error$" { "Ошибка"; break }
      "^Check complete$" { "Проверка выполнена"; break }
      default { $state }
    }

    $displayDetails = ([string]$item.Details) -replace "^StartupType=", "Тип запуска: "
    $item | Add-Member -NotePropertyName DisplayCategory -NotePropertyValue $displayCategory -Force
    $item | Add-Member -NotePropertyName DisplayState -NotePropertyValue $displayState -Force
    $item | Add-Member -NotePropertyName DisplayDetails -NotePropertyValue $displayDetails -Force
  }

  $items = if ($OnlyFound) { @($raw | Where-Object { $_.State -notin @("Not found","Not running") }) } else { $raw }
  $global:CurrentScanDisplayItems = @($items)

  $foundItems = @($raw | Where-Object { $_.State -notin @("Not found","Not running") })
  $categoryCounts = @{
    Services = @($raw | Where-Object { $_.Category -eq "Service" })
    Processes = @($raw | Where-Object { $_.Category -eq "Process" })
    Folders = @($raw | Where-Object {
      $_.Category -eq "Folder" -and
      $_.Source -notlike "*AppData*" -and
      -not [bool]$_.IsProtected
    })
    Registry = @($raw | Where-Object { $_.Category -eq "Registry" })
    AppData = @($raw | Where-Object { $_.Source -like "*AppData*" })
    Programs = @($raw | Where-Object { $_.Category -eq "Installed Program" })
    Protected = @($raw | Where-Object { $_.Category -eq "Protected Folder" -or [bool]$_.IsProtected })
  }

  $controls.lblServicesCount.Text = "$(@($foundItems | Where-Object { $_.Category -eq 'Service' }).Count) из $($categoryCounts.Services.Count)"
  $controls.lblProcessesCount.Text = "$(@($foundItems | Where-Object { $_.Category -eq 'Process' }).Count) из $($categoryCounts.Processes.Count)"
  $controls.lblFoldersCount.Text = "$(@($foundItems | Where-Object {
    $_.Category -eq 'Folder' -and $_.Source -notlike '*AppData*' -and -not [bool]$_.IsProtected
  }).Count) из $($categoryCounts.Folders.Count)"
  $controls.lblRegistryCount.Text = "$(@($foundItems | Where-Object { $_.Category -eq 'Registry' }).Count) из $($categoryCounts.Registry.Count)"
  $controls.lblAppDataCount.Text = "$(@($foundItems | Where-Object { $_.Source -like '*AppData*' }).Count) из $($categoryCounts.AppData.Count)"
  $controls.lblProgramsCount.Text = "$(@($foundItems | Where-Object { $_.Category -eq 'Installed Program' }).Count) из $($categoryCounts.Programs.Count)"
  $controls.lblProtectedCount.Text = "$(@($foundItems | Where-Object {
    $_.Category -eq 'Protected Folder' -or [bool]$_.IsProtected
  }).Count) из $($categoryCounts.Protected.Count)"
  $controls.lblTotalCount.Text = "$($raw.Count) элементов"

  Apply-ScanSearch
}

function Apply-ScanSearch {
  $items = @($global:CurrentScanDisplayItems)
  $query = if ($controls.tbScanSearch) { ([string]$controls.tbScanSearch.Text).Trim() } else { "" }
  if ($query) {
    $items = @($items | Where-Object {
      ([string]$_.DisplayCategory).IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
      ([string]$_.Name).IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
      ([string]$_.DisplayState).IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 -or
      ([string]$_.DisplayDetails).IndexOf($query, [System.StringComparison]::OrdinalIgnoreCase) -ge 0
    })
  }

  $controls.dgScan.ItemsSource = $items
  $rawCount = @($global:LastScanRawItems).Count
  $controls.lblSummary.Text = "Показано: $($items.Count) (всего: $rawCount)"
  if ($items.Count -eq 0) {
    $controls.scanEmptyPanel.Visibility = "Visible"
    if ($null -eq $global:LastScanRawItems) {
      $controls.scanEmptyTitle.Text = "Сканирование ещё не проводилось."
      $controls.scanEmptyHint.Text = "Нажмите «Сканировать» для получения результатов."
    } else {
      $controls.scanEmptyTitle.Text = "Совпадений не найдено."
      $controls.scanEmptyHint.Text = "Измените строку поиска или фильтр результатов."
    }
  } else {
    $controls.scanEmptyPanel.Visibility = "Collapsed"
  }
}

function Set-ScanUiBusy([bool]$Busy) {
  $controls.btnScan.IsEnabled = -not $Busy
  $controls.btnScanResults.IsEnabled = -not $Busy
  $controls.btnRun.IsEnabled = -not $Busy
  $controls.btnAnalyze.IsEnabled = -not $Busy
  $controls.pb.IsIndeterminate = $Busy
  $controls.pb.Visibility = if ($Busy) { "Visible" } else { "Collapsed" }
  if (-not $Busy) {
    $controls.pb.Value = 0
  }
}

function Get-ScanErrorMessage($ErrorObject) {
  if ($null -eq $ErrorObject) { return "Неизвестная ошибка" }

  try {
    if ($ErrorObject.Exception -and -not [string]::IsNullOrWhiteSpace([string]$ErrorObject.Exception.Message)) {
      return [string]$ErrorObject.Exception.Message
    }
  } catch {}

  try {
    if (-not [string]::IsNullOrWhiteSpace([string]$ErrorObject.Message)) {
      return [string]$ErrorObject.Message
    }
  } catch {}

  $message = [string]$ErrorObject
  if ([string]::IsNullOrWhiteSpace($message)) { return "Неизвестная ошибка" }
  return $message
}

function Do-Scan {
  $raw = @(Get-ScanItems `
    -Services @($Services) `
    -Processes @($Processes) `
    -RegistryKeys @($RegistryKeys) `
    -ProgramFolders @($ProgramFolders) `
    -ProtectedFolders @($ProtectedScanFolders) `
    -UninstallRegistryPaths @($UninstallRegistryPaths) `
    -AllUsers ([bool]$controls.rbAll.IsChecked))

  $global:LastScanRawItems = $raw
  Apply-ScanItems -RawItems $raw -OnlyFound ([bool]$controls.cbOnlyFound.IsChecked)
  return ,$raw
}

function Start-ScanAsync {
  if ($global:ScanAsyncTask) {
    Write-UILog "Сканирование уже выполняется." "WARN"
    return
  }

  $controls.tbConsole.Clear()
  Set-ScanUiBusy $true
  Write-UILog "Сканирование запущено..."

  $getUserProfilesDefinition = (Get-Command Get-UserProfiles -CommandType Function).Definition
  $getCiscoInstallCandidatesDefinition = (Get-Command Get-CiscoInstallCandidates -CommandType Function).Definition
  $getScanItemsDefinition = (Get-Command Get-ScanItems -CommandType Function).Definition
  $scanScript = @"
param(
  [string[]]`$Services,
  [string[]]`$Processes,
  [string[]]`$RegistryKeys,
  [string[]]`$ProgramFolders,
  [string[]]`$ProtectedFolders,
  [string[]]`$UninstallRegistryPaths,
  [bool]`$AllUsers
)
function Get-UserProfiles {
$getUserProfilesDefinition
}
function Get-CiscoInstallCandidates {
$getCiscoInstallCandidatesDefinition
}
function Get-ScanItems {
$getScanItemsDefinition
}
Get-ScanItems -Services `$Services -Processes `$Processes -RegistryKeys `$RegistryKeys -ProgramFolders `$ProgramFolders -ProtectedFolders `$ProtectedFolders -UninstallRegistryPaths `$UninstallRegistryPaths -AllUsers `$AllUsers
"@
  $scanInput = @{
    Script = $scanScript
    Services = @($Services)
    Processes = @($Processes)
    RegistryKeys = @($RegistryKeys)
    ProgramFolders = @($ProgramFolders)
    ProtectedFolders = @($ProtectedScanFolders)
    UninstallRegistryPaths = @($UninstallRegistryPaths)
    AllUsers = [bool]$controls.rbAll.IsChecked
  }
  $worker = New-Object System.ComponentModel.BackgroundWorker
  $timer = New-Object System.Windows.Threading.DispatcherTimer
  $timer.Interval = [TimeSpan]::FromSeconds(120)
  $scanState = [PSCustomObject]@{
    Worker = $worker
    Timer = $timer
    Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    TimedOut = $false
  }
  $global:ScanAsyncTask = $scanState

  $doWorkMethod = [ScanBackgroundWorkerHost].GetMethod("Run")
  $doWorkHandler = [System.Delegate]::CreateDelegate([System.ComponentModel.DoWorkEventHandler], $doWorkMethod)
  $worker.add_DoWork($doWorkHandler)

  $completedHandler = {
    param($sender, $e)
    $scanState.Timer.Stop()
    $scanState.Stopwatch.Stop()

    if ($scanState.TimedOut) {
      return
    }

    Set-ScanUiBusy $false
    $global:ScanAsyncTask = $null
    $seconds = $scanState.Stopwatch.Elapsed.TotalSeconds.ToString("0.0")

    if ($e.Error) {
      $errorMessage = Get-ScanErrorMessage $e.Error
      Write-UILog ("Ошибка сканирования через {0} сек.: {1}" -f $seconds, $errorMessage) "ERROR"
      return
    }

    $global:LastScanRawItems = @($e.Result)
    Apply-ScanItems -RawItems $global:LastScanRawItems -OnlyFound ([bool]$controls.cbOnlyFound.IsChecked)
    Write-UILog ("Сканирование завершено за {0} сек. Найдено элементов: {1}" -f $seconds, $global:LastScanRawItems.Count)
  }.GetNewClosure()
  $worker.add_RunWorkerCompleted($completedHandler)

  $timeoutHandler = {
    $scanState.Timer.Stop()
    if ($scanState.TimedOut) { return }

    $scanState.TimedOut = $true
    $scanState.Stopwatch.Stop()
    Set-ScanUiBusy $false
    $global:ScanAsyncTask = $null
    Write-UILog "Сканирование прервано по тайм-ауту через 120 секунд." "ERROR"
  }.GetNewClosure()
  $timer.add_Tick($timeoutHandler)

  try {
    $timer.Start()
    $worker.RunWorkerAsync($scanInput)
  } catch {
    $timer.Stop()
    $scanState.Stopwatch.Stop()
    Set-ScanUiBusy $false
    $global:ScanAsyncTask = $null
    $errorMessage = Get-ScanErrorMessage $_
    Write-UILog ("Ошибка сканирования через {0} сек.: {1}" -f $scanState.Stopwatch.Elapsed.TotalSeconds.ToString("0.0"), $errorMessage) "ERROR"
  }
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

function Backup-FolderSafe([string]$SourcePath,[string]$OutputZipPath){
  try{
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)){
      Write-UILog ("Backup folder skipped, source not found: {0}" -f $SourcePath) "WARN"
      return $false
    }

    $zipDir = [System.IO.Path]::GetDirectoryName($OutputZipPath)
    if (-not [string]::IsNullOrWhiteSpace($zipDir)){
      New-Item -ItemType Directory -Path $zipDir -Force -ErrorAction Stop | Out-Null
    }

    Add-Type -AssemblyName 'System.IO.Compression.FileSystem' -ErrorAction Stop

    $targetZip = $OutputZipPath
    if (Test-Path -LiteralPath $targetZip){
      $baseName = [System.IO.Path]::GetFileNameWithoutExtension($OutputZipPath)
      $extension = [System.IO.Path]::GetExtension($OutputZipPath)
      $parent = [System.IO.Path]::GetDirectoryName($OutputZipPath)
      $i = 1
      do {
        $targetZip = Join-Path $parent ("{0}_{1}{2}" -f $baseName,$i,$extension)
        $i++
      } while (Test-Path -LiteralPath $targetZip)
    }

    [System.IO.Compression.ZipFile]::CreateFromDirectory($SourcePath,$targetZip)
    if (-not (Test-Path -LiteralPath $targetZip)){
      Write-UILog ("Backup folder failed for {0}: zip was not created: {1}" -f $SourcePath,$targetZip) "ERROR"
      return $false
    }

    Write-UILog ("Backup {0} -> {1}" -f $SourcePath,$targetZip)
    return $true
  } catch {
    Write-UILog ("Backup folder failed for {0}: {1}" -f $SourcePath, $_.Exception.Message) "ERROR"
    return $false
  }
}

function Remove-CiscoFolders([bool]$WhatIf,[bool]$Backup,[bool]$Force,$Selection){
  $targets = if ($Selection){
    $Selection |
      Where-Object { $_.Category -eq "Folder" -and -not [bool]$_.IsProtected -and [bool]$_.IsRemovable } |
      ForEach-Object { $_.Path }
  } else {
    Get-TargetFolders
  }
  foreach($path in $targets){
    if (Test-IsBlockedFolderRoot $path){
      Write-UILog ("BLOCKED safety: broad Cisco folder will not be removed: {0}" -f $path) "WARN"
      continue
    }
    if (Test-Path -LiteralPath $path -PathType Container){
      if ($WhatIf){ Write-UILog ("WHATIF: remove dir {0}" -f $path) }
      else{
        if ($Backup){
          $zip = Join-Path $global:CleanupRoot ("{0}_{1:yyyyMMdd_HHmmss}.zip" -f ((Split-Path $path -Leaf) -replace '[^\w\-\.]','_'), (Get-Date))
          if (-not (Backup-FolderSafe -SourcePath $path -OutputZipPath $zip)){
            Write-UILog ("Skip remove dir {0}: backup failed" -f $path) "ERROR"
            continue
          }
        }

        try{
          Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
          Write-UILog ("Removed dir {0}" -f $path)
        } catch {
          $err = $_.Exception.Message
          if ($Force){
            try{
              Get-ChildItem -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue | % { $_.Attributes='Normal' }
              Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
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

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)){
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
    $gf = @(); foreach($d in $GoodbyeFiles){ if (Test-Path -LiteralPath $d -PathType Container){ $gf += $d } }
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

function Show-SuspiciousAdapters {
  $controls.tbDiag.Clear()
  Write-Diag "=== Подозрительные сетевые адаптеры ==="
  $ifaces = Get-NetAdapter -Physical:$false -ErrorAction SilentlyContinue
  $targets = @()
  foreach($i in $ifaces){
    foreach($p in $AdapterPatterns){
      if ($i.Name -like "*$p*" -or $i.InterfaceDescription -like "*$p*"){ $targets += $i; break }
    }
  }
  if (-not $targets.Count){
    Write-Diag "Подозрительных адаптеров не найдено."
    return
  }

  foreach($adapter in ($targets | Sort-Object Name -Unique)){
    Write-Diag ("Адаптер: {0}; Статус: {1}; Описание: {2}; MAC: {3}" -f `
      $adapter.Name, $adapter.Status, $adapter.InterfaceDescription, $adapter.MacAddress)
  }
  Write-Diag ("Итого найдено: {0}. Изменения в систему не вносились." -f @($targets | Sort-Object Name -Unique).Count)
}

function Update-ScanColumnWidths {
  if (-not $controls.dgScan -or $controls.dgScan.Columns.Count -lt 5) { return }

  $gridWidth = [double]$controls.dgScan.ActualWidth
  if ($gridWidth -lt 600) { return }

  $availableWidth = [Math]::Max(360, $gridWidth - 348)
  $objectWidth = [Math]::Max(180, [Math]::Floor($availableWidth * 0.42))
  $detailsWidth = [Math]::Max(180, $availableWidth - $objectWidth)
  $controls.dgScan.Columns[2].Width = New-Object -TypeName System.Windows.Controls.DataGridLength -ArgumentList ([double]$objectWidth)
  $controls.dgScan.Columns[4].Width = New-Object -TypeName System.Windows.Controls.DataGridLength -ArgumentList ([double]$detailsWidth)
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
$controls.btnScan.Add_Click({ Start-ScanAsync })
$controls.btnScanResults.Add_Click({ Start-ScanAsync })
$controls.dgScan.Add_Loaded({ Update-ScanColumnWidths })
$controls.dgScan.Add_SizeChanged({ Update-ScanColumnWidths })
$controls.tbScanSearch.Add_TextChanged({ Apply-ScanSearch })
$controls.cbOnlyFound.Add_Click({
  if ($null -ne $global:LastScanRawItems) {
    Apply-ScanItems -RawItems $global:LastScanRawItems -OnlyFound ([bool]$controls.cbOnlyFound.IsChecked)
  } else {
    Write-UILog "Сначала выполните сканирование. Запускается фоновое сканирование..."
    Start-ScanAsync
  }
})
$controls.btnExportCsv.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Join-Path $global:CleanupRoot "scan.csv"; $items|Export-Csv -Path $p -NoTypeInformation -Encoding UTF8; Write-UILog ("Экспорт CSV: {0}" -f $p); Start-Process $p } })
$controls.btnExportJson.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Join-Path $global:CleanupRoot "scan.json"; $items|ConvertTo-Json -Depth 4|Set-Content -Path $p -Encoding UTF8; Write-UILog ("Экспорт JSON: {0}" -f $p); Start-Process $p } })
$controls.btnExportHtml.Add_Click({ $items=$controls.dgScan.ItemsSource; if($items){ $p=Resolve-Env $controls.tbHtmlPath.Text; Save-HtmlReport -Items $items -Path $p; Write-UILog ("Экспорт HTML: {0}" -f $p); Start-Process $p } })
$controls.btnPing.Add_Click({
  $consoleStart = ([string]$controls.tbConsole.Text).Length
  Invoke-PingFirstBit
  $consoleText = [string]$controls.tbConsole.Text
  if ($consoleText.Length -gt $consoleStart) {
    $pingOutput = $consoleText.Substring($consoleStart)
    $controls.tbDiag.AppendText($pingOutput)
    $controls.tbDiag.ScrollToEnd()
  }
})
$controls.btnOpenLog.Add_Click({ $p=Resolve-Env $controls.tbLogPath.Text; if(Test-Path -LiteralPath $p -PathType Leaf){ Start-Process $p } })
$controls.btnOpenHtml.Add_Click({ $p=Resolve-Env $controls.tbHtmlPath.Text; if(Test-Path -LiteralPath $p -PathType Leaf){ Start-Process $p } })
$controls.btnAnalyze.Add_Click({
  $controls.tbConsole.Clear()
  Run-Flow ($controls.cbFull.IsChecked) ($controls.cbServices.IsChecked) ($controls.cbFolders.IsChecked) ($controls.cbRegistry.IsChecked) ($controls.cbBackup.IsChecked) ($controls.cbForce.IsChecked) $true ($controls.cbHtml.IsChecked) $false ($controls.cbSelectionOnly.IsChecked)
})
$controls.btnRun.Add_Click({
  $controls.tbConsole.Clear()
  $r = [System.Windows.MessageBox]::Show(
    "Выполнить очистку? Это действие может изменить сетевые настройки системы.",
    "Подтверждение очистки",
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

$controls.btnClearLog.Add_Click({
  $controls.tbConsole.Clear()
})
$controls.btnClearDiag.Add_Click({
  $controls.tbDiag.Clear()
})
$controls.btnCopyDiag.Add_Click({
  if ([string]::IsNullOrWhiteSpace([string]$controls.tbDiag.Text)) { return }
  try {
    [System.Windows.Clipboard]::SetText([string]$controls.tbDiag.Text)
  } catch {
    Write-UILog ("Не удалось скопировать диагностику в буфер обмена: {0}" -f $_.Exception.Message) "WARN"
  }
})

$controls.btnDiag.Add_Click({ $controls.tbDiag.Clear(); Test-VpnDiagnostics -TargetHost "vpn.1cbit.ru" })
$controls.btnDisableAdapters.Add_Click({ Show-SuspiciousAdapters })
$controls.btnStopGoodbye.Add_Click({ Stop-ConflictTools })

$window.ShowDialog() | Out-Null
